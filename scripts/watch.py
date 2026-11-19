#!/usr/bin/env python3
"""watch.py — read-only live teaching overlay for Agent Stack delivery runs.

Serves one self-contained viewer page plus JSON APIs backed by
.agent-stack/runs/<run-id>/state.json and append-only events.jsonl.
Read-only: only GET is implemented; the server never writes to the run.

Usage:
  watch.py [--run <run-id>] [--root PATH] [--kit-root PATH]
           [--host 127.0.0.1] [--port 4311] [--open | --no-open]

Without --run the server starts immediately (even before any run exists)
and the viewer follows the most recently updated run, picking up new runs
as they appear. With --run it pins to one run. Stop with Ctrl-C.

Endpoints:
  GET /                    Viewer page (template from
                           .agent-stack/templates/watch/watch.html)
  GET /api/runs            All runs as {"runs": [{runId, phase, changeId,
                           issueId, updatedAt}]}, newest first
  GET /api/state[?run=ID]  Run state.json (404 when the run is unknown;
                           without ?run= uses the pinned or latest run)
  GET /api/events[?run=ID][&since=N]
                           Events after line offset N as
                           {"runId": ID, "events": [...], "nextOffset": M}
  GET /api/meta            {"mode": "pinned"|"follow", "runId": ...} plus
                           resolved OpenCode models + Jev routing from the
                           target project's .agent-stack/config.conf
  GET /api/transcript[?run=ID][&since=N]
                           What each agent ran and said, read from the
                           harness's own local session store (Claude Code
                           JSONL transcripts, OpenCode's SQLite database),
                           limited to sessions of this project that mention
                           the run, inside the run's time window. Secrets are
                           redacted and long outputs clipped. Disabled with
                           --no-transcripts.

Stdlib only.
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import threading
import time
from datetime import datetime, timezone
from urllib.parse import quote
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")

ROLE_MODEL_KEYS = (
    ("resolver", "OPENCODE_RESOLVER_MODEL", "OPENCODE_RESOLVER_VARIANT"),
    ("designer", "OPENCODE_DESIGNER_MODEL", "OPENCODE_DESIGNER_VARIANT"),
    ("design-qa", "OPENCODE_DESIGN_QA_MODEL", "OPENCODE_DESIGN_QA_VARIANT"),
    ("developer", "OPENCODE_DEVELOPER_MODEL", "OPENCODE_DEVELOPER_VARIANT"),
    ("web-qa", "OPENCODE_WEB_QA_MODEL", "OPENCODE_WEB_QA_VARIANT"),
    ("mobile-qa", "OPENCODE_MOBILE_QA_MODEL", "OPENCODE_MOBILE_QA_VARIANT"),
)


def read_config(path):
    values = {}
    if not os.path.isfile(path):
        return values
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            # Match setup-agent-stack.sh get_config(): the first occurrence wins.
            values.setdefault(key.strip(), value.strip())
    return values


def detect_harness(root, config):
    """Name the host actually running Agent Stack, from installed markers.

    The run events do not carry a host field, so this is reported as project
    configuration, not as an observed run attribute.
    """
    markers = (
        ("opencode", "OpenCode", os.path.join(root, ".opencode"),
         "ENABLE_OPENCODE"),
        ("claude", "Claude Code", os.path.join(root, ".claude"),
         "ENABLE_CLAUDE"),
        ("codex", "Codex", os.path.join(root, ".codex"),
         "ENABLE_CODEX"),
        ("cursor", "Cursor", os.path.join(root, ".cursor"),
         "ENABLE_CURSOR"),
    )
    found = []
    for platform, name, marker, flag in markers:
        if os.path.isdir(marker) or config.get(flag) == "1":
            found.append({"platform": platform, "name": name})
    if not found:
        found.append({"platform": "unknown", "name": "Harness not reported"})
    version = config.get("AGENT_STACK_VERSION", "")
    if not version:
        try:
            with open(os.path.join(root, ".agent-stack", ".kit-version"),
                      encoding="utf-8") as fh:
                version = fh.read().strip()
        except OSError:
            pass
    return {
        "name": " + ".join(item["name"] for item in found),
        "platforms": [item["platform"] for item in found],
        "version": version,
        "source": "Project configuration",
    }


def run_dir(root, run_id):
    return os.path.join(root, ".agent-stack", "runs", run_id)


def check_run_id(run_id):
    """Return an error string when run_id is unusable, else None."""
    if not RUN_ID_RE.match(run_id or ""):
        return "invalid run id %r (use [A-Za-z0-9._-])" % (run_id,)
    return None


def list_runs(root):
    """Summarize every run newest-first. Never raises on bad data."""
    runs_root = os.path.join(root, ".agent-stack", "runs")
    found = []
    if not os.path.isdir(runs_root):
        return found
    for name in sorted(os.listdir(runs_root)):
        state_file = os.path.join(runs_root, name, "state.json")
        if not os.path.isfile(state_file):
            continue
        if check_run_id(name):
            continue
        try:
            with open(state_file, encoding="utf-8") as fh:
                state = json.load(fh)
        except (OSError, ValueError):
            continue
        if not isinstance(state, dict):
            continue
        found.append({
            "runId": state.get("runId", name),
            "phase": state.get("phase"),
            "changeId": state.get("changeId"),
            "issueId": state.get("issueId"),
            "updatedAt": state.get("updatedAt", ""),
        })
    found.sort(key=lambda r: r["updatedAt"], reverse=True)
    return found


# ---------------------------------------------------------------------------
# Harness transcripts
#
# Self-reported notes are sparse; the harness already records every tool call,
# result, visible message and (when the model exposes it) reasoning. Reading
# that local record is what makes the viewer look like the terminal. Only the
# project's own sessions that mention the run are read, inside the run's time
# window, read-only.

AGENT_ROLES = ("resolver", "designer", "design-qa", "developer", "web-qa",
               "mobile-qa", "jev")
TERMINAL_PHASES = ("awaiting_merge", "dropped", "blocked", "done", "closed")
WINDOW_BEFORE = 15 * 60   # preflight work before `run-state init`
WINDOW_AFTER = 10 * 60    # closing messages after the last run event
OUTPUT_MAX_CHARS = 12000
OUTPUT_MAX_LINES = 200
TEXT_MAX_CHARS = 20000
INPUT_MAX_CHARS = 8000
MAX_ENTRIES = 20000

SECRET_PATTERNS = (
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
     "[redacted private key]"),
    (re.compile(r"\bsk-(?:ant-|proj-|or-)?[A-Za-z0-9_-]{16,}"), "[redacted key]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"), "[redacted token]"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"), "[redacted token]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[redacted key]"),
    (re.compile(r"\bAIza[0-9A-Za-z_-]{30,}"), "[redacted key]"),
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{16,}"), r"\1 [redacted]"),
    (re.compile(r"(?i)\b([A-Z0-9_]*(?:api[_-]?key|secret|token|password|passwd|credential)[A-Z0-9_]*)"
                r"(['\"]?\s*[:=]\s*)(['\"]?)(?!\[redacted)([^\s'\",}]{6,})"), r"\1\2\3[redacted]"),
)


def redact(text):
    if not isinstance(text, str) or not text:
        return text or ""
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def clip(text, max_chars, max_lines=None):
    """Return (clipped_text, total_lines, truncated)."""
    text = redact(text if isinstance(text, str) else json.dumps(text, indent=2))
    total = text.count("\n") + 1 if text else 0
    truncated = False
    if max_lines and total > max_lines:
        text = "\n".join(text.split("\n")[:max_lines])
        truncated = True
    if len(text) > max_chars:
        text = text[:max_chars]
        truncated = True
    return text, total, truncated


def iso_ms(value):
    try:
        return datetime.fromtimestamp(float(value) / 1000.0, tz=timezone.utc) \
            .isoformat().replace("+00:00", "Z")
    except (TypeError, ValueError, OverflowError, OSError):
        return ""


def parse_ts(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def within(path, root):
    path = os.path.normpath(path or "")
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def relative_path(path, root):
    if isinstance(path, str) and within(path, root) and path != root:
        return os.path.relpath(path, root)
    return path or ""


def tool_title(name, data, root):
    """One-line summary of a tool call, like the harness prints it."""
    data = data if isinstance(data, dict) else {}

    def pick(*keys):
        for key in keys:
            value = data.get(key)
            if isinstance(value, str) and value:
                return value
        return ""
    low = (name or "").lower()
    if low in ("bash", "shell", "exec", "run"):
        return pick("command", "cmd")
    if low in ("read", "write", "edit", "multiedit", "notebookedit", "patch", "view"):
        return relative_path(pick("file_path", "filePath", "path", "notebook_path"), root)
    if low == "grep":
        where = relative_path(pick("path", "include", "glob"), root)
        return pick("pattern") + (" in " + where if where else "")
    if low in ("glob", "list", "ls"):
        return pick("pattern") or relative_path(pick("path"), root)
    if low in ("task", "agent"):
        kind = pick("subagent_type", "subagentType", "agent")
        return (kind + ": " if kind else "") + pick("description", "prompt")[:160]
    if low == "skill":
        return pick("skill", "id", "name")
    if low in ("webfetch", "web_fetch", "fetch"):
        return pick("url")
    if low in ("websearch", "web_search"):
        return pick("query")
    if low == "todowrite":
        todos = data.get("todos")
        return "%d todos" % len(todos) if isinstance(todos, list) else ""
    text = json.dumps(data, ensure_ascii=False)
    return text if len(text) <= 160 else text[:159] + "…"


def tool_display_name(name):
    name = name or "tool"
    if name.startswith("mcp__"):
        parts = name.split("__")
        return " · ".join(p for p in parts[1:] if p) or name
    return name[:1].upper() + name[1:]


def tool_diff(name, data):
    """A short diff for edits and writes, the way the harness shows them."""
    if not isinstance(data, dict):
        return ""
    low = (name or "").lower()
    old = data.get("old_string", data.get("oldString"))
    new = data.get("new_string", data.get("newString"))
    lines = []
    if isinstance(old, str) and isinstance(new, str):
        lines += ["- " + line for line in old.split("\n")]
        lines += ["+ " + line for line in new.split("\n")]
    elif low == "write" and isinstance(data.get("content"), str):
        lines += ["+ " + line for line in data["content"].split("\n")]
    elif isinstance(data.get("edits"), list):
        for edit in data["edits"][:6]:
            if isinstance(edit, dict):
                lines += ["- " + line for line in str(edit.get("old_string", "")).split("\n")]
                lines += ["+ " + line for line in str(edit.get("new_string", "")).split("\n")]
    if not lines:
        return ""
    text, _, _ = clip("\n".join(lines), 6000, 80)
    return text


def content_text(content):
    """Flatten tool-result content (string or list of blocks) into text."""
    if isinstance(content, str):
        return content
    parts = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    parts.append(block.get("text") or "")
                elif block.get("type") == "image":
                    parts.append("[image]")
                elif "text" in block:
                    parts.append(str(block.get("text") or ""))
            elif isinstance(block, str):
                parts.append(block)
    return "\n".join(parts)


TAG_BLOCK_RE = re.compile(r"<(system-reminder|local-command-caveat|local-command-stdout|"
                          r"local-command-stderr|command-message)>[\s\S]*?</\1>")


def prompt_text(text):
    """Strip harness wrappers from a user prompt; '' when nothing human remains."""
    if not isinstance(text, str):
        return ""
    name = re.search(r"<command-name>([\s\S]*?)</command-name>", text)
    args = re.search(r"<command-args>([\s\S]*?)</command-args>", text)
    if name:
        return (name.group(1).strip() + " " + (args.group(1).strip() if args else "")).strip()
    text = TAG_BLOCK_RE.sub("", text)
    return text.strip()


class TranscriptIndex:
    """Incrementally reads harness transcripts for one run.

    Entries get a monotonically increasing ``seq`` as they are discovered;
    clients ask for ``since=<seq>``. Tool results are separate entries that
    reference their call through ``callId``.
    """

    def __init__(self, root, run_id, claude_dir=None, opencode_db=None):
        self.root = os.path.normpath(os.path.abspath(root))
        self.run_id = run_id
        self.claude_dir = claude_dir
        self.opencode_db = opencode_db
        self.lock = threading.Lock()
        self.entries = []
        self.seq = 0
        self.files = {}          # path -> {"offset", "buffer", "agent", ...}
        self.members = {}        # claude main session path -> bool
        self.member_checked = {}
        self.oc_sessions = {}    # opencode session id -> {"agent", "seen", ...}
        self.oc_member = {}
        self.oc_checked = {}
        self.sources = {}
        self.last_discovery = 0.0
        self.last_read = 0.0
        self.window = (0.0, 0.0)
        self.errors = []

    # -- shared --------------------------------------------------------------
    def _emit(self, entry):
        self.seq += 1
        entry["seq"] = self.seq
        self.entries.append(entry)
        if len(self.entries) > MAX_ENTRIES:
            del self.entries[:len(self.entries) - MAX_ENTRIES]

    def _in_window(self, ts):
        at = parse_ts(ts)
        return at is None or self.window[0] <= at <= self.window[1]

    def compute_window(self):
        events_file = os.path.join(run_dir(self.root, self.run_id), "events.jsonl")
        first = last = None
        try:
            with open(events_file, encoding="utf-8") as fh:
                for line in fh:
                    try:
                        at = parse_ts(json.loads(line).get("ts"))
                    except ValueError:
                        continue
                    if at is None:
                        continue
                    first = at if first is None else min(first, at)
                    last = at if last is None else max(last, at)
        except OSError:
            pass
        phase = None
        try:
            with open(os.path.join(run_dir(self.root, self.run_id), "state.json"),
                      encoding="utf-8") as fh:
                phase = json.load(fh).get("phase")
        except (OSError, ValueError, AttributeError):
            pass
        now = time.time()
        if first is None:
            return (now - WINDOW_BEFORE, now + 60)
        end = last + WINDOW_AFTER if phase in TERMINAL_PHASES else now + 60
        return (first - WINDOW_BEFORE, end)

    def refresh(self):
        with self.lock:
            now = time.time()
            if now - self.last_read < 0.4:
                return
            self.last_read = now
            self.window = self.compute_window()
            discover = now - self.last_discovery > 3.0
            if discover:
                self.last_discovery = now
            try:
                self._claude(discover)
            except OSError as exc:
                self._note_error("Claude Code transcripts: %s" % exc)
            try:
                self._opencode(discover)
            except (sqlite3.Error, OSError) as exc:
                self._note_error("OpenCode session store: %s" % exc)

    def _note_error(self, message):
        if message not in self.errors:
            self.errors.append(message)
            del self.errors[:-5]

    def snapshot(self, since):
        with self.lock:
            entries = [e for e in self.entries if e["seq"] > since]
            return {"entries": entries, "nextSeq": self.seq,
                    "sources": sorted(self.sources.values(),
                                      key=lambda s: (s.get("started") or "", s["id"])),
                    "window": {"start": iso_ms(self.window[0] * 1000),
                               "end": iso_ms(self.window[1] * 1000)},
                    "errors": list(self.errors)}

    # -- Claude Code -----------------------------------------------------------
    def _claude(self, discover):
        base = self.claude_dir
        if base is None:
            home = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
            base = os.path.join(home, "projects")
        if not os.path.isdir(base):
            return
        if discover:
            slug = re.sub(r"[^A-Za-z0-9]", "-", self.root)
            for name in os.listdir(base):
                if name != slug and not name.startswith(slug + "-"):
                    continue
                folder = os.path.join(base, name)
                try:
                    listing = os.listdir(folder)
                except OSError:
                    continue
                for entry in listing:
                    if not entry.endswith(".jsonl"):
                        continue
                    path = os.path.join(folder, entry)
                    try:
                        stat = os.stat(path)
                    except OSError:
                        continue
                    if stat.st_mtime < self.window[0]:
                        continue
                    if not self.members.get(path) and \
                            now_minus(self.member_checked.get(path)) > 10:
                        self.member_checked[path] = time.time()
                        self.members[path] = file_mentions(path, self.run_id)
                    if self.members.get(path):
                        self._claude_session(path)
        for path, state in list(self.files.items()):
            if state["harness"] == "claude-code":
                self._claude_read(path, state)

    def _claude_session(self, path):
        session = os.path.basename(path)[:-len(".jsonl")]
        if path not in self.files:
            self.files[path] = {"harness": "claude-code", "offset": 0, "buffer": b"",
                                "agent": "resolver", "session": session, "main": True,
                                "prompted": True, "tools": {}}
        subagents = os.path.join(os.path.dirname(path), session, "subagents")
        if not os.path.isdir(subagents):
            self._claude_source(path)
            return
        children = []
        for entry in sorted(os.listdir(subagents)):
            if not entry.endswith(".jsonl"):
                continue
            child = os.path.join(subagents, entry)
            agent_type = ""
            try:
                with open(child[:-len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
                    meta = json.load(fh)
                agent_type = str(meta.get("agentType") or "")
            except (OSError, ValueError, AttributeError):
                meta = {}
            children.append(agent_type)
            if child not in self.files:
                self.files[child] = {"harness": "claude-code", "offset": 0, "buffer": b"",
                                     "agent": agent_type or "subagent", "session": session,
                                     "subagent": entry[len("agent-"):-len(".jsonl")] if entry.startswith("agent-") else entry,
                                     "description": str(meta.get("description") or ""),
                                     "finished": bool(meta.get("finished")),
                                     "main": False, "prompted": False, "tools": {}}
            else:
                self.files[child]["finished"] = bool(meta.get("finished"))
        # When the resolver itself runs as a subagent, the main session is the
        # human's orchestrating session, not the resolver.
        if "resolver" in children:
            self.files[path]["agent"] = "main"
        self._claude_source(path)

    def _claude_source(self, path):
        state = self.files[path]
        key = "cc:" + path
        self.sources[key] = {
            "id": key, "harness": "claude-code", "agent": state["agent"],
            "session": state["session"][:8], "subagent": state.get("subagent", ""),
            "title": state.get("description", ""), "model": state.get("model", ""),
            "started": state.get("started", ""), "finished": state.get("finished", False),
        }

    def _claude_read(self, path, state):
        try:
            size = os.path.getsize(path)
        except OSError:
            return
        if size < state["offset"]:
            state["offset"], state["buffer"] = 0, b""
        if size == state["offset"]:
            return
        with open(path, "rb") as fh:
            fh.seek(state["offset"])
            chunk = fh.read(size - state["offset"])
        state["offset"] = size
        data = state["buffer"] + chunk
        lines = data.split(b"\n")
        state["buffer"] = lines.pop()
        for raw in lines:
            if not raw.strip():
                continue
            try:
                obj = json.loads(raw)
            except ValueError:
                continue
            if isinstance(obj, dict):
                self._claude_line(path, state, obj)
        self._claude_source(path)

    def _claude_line(self, path, state, obj):
        kind = obj.get("type")
        if kind not in ("assistant", "user"):
            return
        cwd = obj.get("cwd")
        if isinstance(cwd, str) and cwd and not within(cwd, self.root):
            return
        ts = obj.get("timestamp") or ""
        if not self._in_window(ts):
            return
        if not state.get("started"):
            state["started"] = ts
        base = {"agent": state["agent"], "harness": "claude-code",
                "session": state["session"][:8], "subagent": state.get("subagent", ""), "ts": ts}
        uid = str(obj.get("uuid") or "")
        message = obj.get("message") if isinstance(obj.get("message"), dict) else {}
        content = message.get("content")
        if kind == "assistant":
            if message.get("model") and not state.get("model") and message["model"] != "<synthetic>":
                state["model"] = message["model"]
            for index, block in enumerate(content if isinstance(content, list) else []):
                if not isinstance(block, dict):
                    continue
                key = "cc:%s:%s:%d" % (state["session"][:8] + state.get("subagent", ""), uid, index)
                btype = block.get("type")
                if btype in ("thinking", "redacted_thinking"):
                    text, _, truncated = clip(block.get("thinking") or "", TEXT_MAX_CHARS)
                    self._emit(dict(base, id=key, kind="thinking", text=text.strip(),
                                    hidden=not text.strip(), truncated=truncated))
                elif btype == "text":
                    text, _, truncated = clip(block.get("text") or "", TEXT_MAX_CHARS)
                    if text.strip():
                        self._emit(dict(base, id=key, kind="text", text=text.strip(), truncated=truncated))
                elif btype == "tool_use":
                    name = str(block.get("name") or "tool")
                    data = block.get("input") if isinstance(block.get("input"), dict) else {}
                    call = str(block.get("id") or key)
                    state["tools"][call] = name
                    shown, _, _ = clip(json.dumps(data, indent=2, ensure_ascii=False), INPUT_MAX_CHARS)
                    title, _, _ = clip(tool_title(name, data, self.root), INPUT_MAX_CHARS)
                    self._emit(dict(base, id=key, kind="tool", tool=tool_display_name(name),
                                    title=title, input=shown, diff=tool_diff(name, data), callId=call))
            return
        if obj.get("isMeta"):
            return
        if isinstance(content, str):
            text = prompt_text(content)
            if text:
                label = "prompt" if state["main"] or state["prompted"] else "delegation"
                state["prompted"] = True
                clipped, lines, truncated = clip(text, TEXT_MAX_CHARS)
                self._emit(dict(base, id="cc:%s:%s" % (state["session"][:8] + state.get("subagent", ""), uid),
                                kind="prompt", text=clipped, role=label, lines=lines, truncated=truncated))
            return
        for index, block in enumerate(content if isinstance(content, list) else []):
            if not isinstance(block, dict):
                continue
            key = "cc:%s:%s:%d" % (state["session"][:8] + state.get("subagent", ""), uid, index)
            if block.get("type") == "tool_result":
                call = str(block.get("tool_use_id") or "")
                output, lines, truncated = clip(content_text(block.get("content")),
                                                OUTPUT_MAX_CHARS, OUTPUT_MAX_LINES)
                self._emit(dict(base, id=key, kind="result", callId=call,
                                tool=tool_display_name(state["tools"].get(call, "")),
                                output=output, lines=lines, truncated=truncated,
                                error=bool(block.get("is_error"))))
            elif block.get("type") == "text":
                text = prompt_text(block.get("text") or "")
                if text:
                    label = "prompt" if state["main"] or state["prompted"] else "delegation"
                    state["prompted"] = True
                    clipped, lines, truncated = clip(text, TEXT_MAX_CHARS)
                    self._emit(dict(base, id=key, kind="prompt", text=clipped, role=label,
                                    lines=lines, truncated=truncated))

    # -- OpenCode ---------------------------------------------------------------
    def _opencode_path(self):
        if self.opencode_db is not None:
            return self.opencode_db
        override = os.environ.get("ASTACK_OPENCODE_DB")
        if override:
            return override
        data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
        return os.path.join(data, "opencode", "opencode.db")

    def _opencode(self, discover):
        path = self._opencode_path()
        if not path or not os.path.isfile(path):
            return
        if not discover and not self.oc_sessions:
            return
        con = sqlite3.connect("file:%s?mode=ro" % quote(path), uri=True, timeout=0.5,
                              check_same_thread=False)
        try:
            con.execute("PRAGMA query_only = 1")
            tables = {row[0] for row in con.execute(
                "select name from sqlite_master where type='table' and name in ('session_v2','session_message')")}
            if tables != {"session_v2", "session_message"}:
                return
            if discover:
                self._opencode_discover(con)
            for sid, state in list(self.oc_sessions.items()):
                self._opencode_read(con, sid, state)
        finally:
            con.close()

    def _opencode_discover(self, con):
        start_ms, end_ms = self.window[0] * 1000, self.window[1] * 1000
        prefix = self.root.rstrip(os.sep) + os.sep
        rows = con.execute(
            "select id, parent_id, directory, title, agent, model, time_created, time_updated "
            "from session_v2 where time_updated >= ? and time_created <= ? and "
            "(directory = ? or substr(directory, 1, ?) = ?)",
            (start_ms, end_ms, self.root, len(prefix), prefix)).fetchall()
        sessions = {row[0]: row for row in rows}
        now = time.time()
        for sid, row in sessions.items():
            if self.oc_member.get(sid):
                continue
            if now_minus(self.oc_checked.get(sid)) < 10:
                continue
            self.oc_checked[sid] = now
            hit = con.execute("select 1 from session_message where session_id = ? and "
                              "instr(data, ?) > 0 limit 1", (sid, self.run_id)).fetchone()
            self.oc_member[sid] = bool(hit)
        # Children of a member session belong to the run as well.
        changed = True
        while changed:
            changed = False
            for sid, row in sessions.items():
                if not self.oc_member.get(sid) and row[1] and self.oc_member.get(row[1]):
                    self.oc_member[sid] = True
                    changed = True
        children_agents = {}
        for sid, row in sessions.items():
            if row[1]:
                children_agents.setdefault(row[1], set()).add(row[4] or "")
        for sid, row in sessions.items():
            if not self.oc_member.get(sid):
                continue
            agent = row[4] or ""
            is_root = not row[1] or row[1] not in sessions or not self.oc_member.get(row[1])
            if agent not in AGENT_ROLES:
                if is_root:
                    agent = "main" if "resolver" in children_agents.get(sid, set()) else "resolver"
                else:
                    agent = agent or "subagent"
            model = ""
            try:
                model_obj = json.loads(row[5] or "{}")
                model = "/".join(x for x in (model_obj.get("providerID"), model_obj.get("id")) if x)
                if model_obj.get("variant"):
                    model += " · " + str(model_obj["variant"])
            except (ValueError, AttributeError):
                pass
            state = self.oc_sessions.setdefault(sid, {"seen": {}, "last": 0, "tools": {},
                                                      "prompted": is_root})
            state.update(agent=agent, title=row[3] or "", model=model, root=is_root,
                         started=iso_ms(row[6]))
            self.sources["oc:" + sid] = {
                "id": "oc:" + sid, "harness": "opencode", "agent": agent, "session": sid[-8:],
                "subagent": "" if is_root else sid[-8:], "title": row[3] or "", "model": model,
                "started": iso_ms(row[6]), "finished": False,
            }

    def _opencode_read(self, con, sid, state):
        rows = con.execute(
            "select id, type, seq, time_created, time_updated, data from session_message "
            "where session_id = ? and time_updated >= ? order by seq",
            (sid, state["last"])).fetchall()
        for mid, mtype, _seq, created, updated, raw in rows:
            state["last"] = max(state["last"], updated or 0)
            try:
                data = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(data, dict):
                continue
            mtime = data.get("time") if isinstance(data.get("time"), dict) else {}
            ts = iso_ms(mtime.get("created") or created)
            if not self._in_window(ts):
                continue
            seen = state["seen"].setdefault(mid, {"items": set(), "results": set()})
            base = {"agent": state["agent"], "harness": "opencode", "session": sid[-8:],
                    "subagent": "" if state.get("root") else sid[-8:], "ts": ts}
            if mtype == "user":
                if "prompt" in seen["items"]:
                    continue
                seen["items"].add("prompt")
                text = data.get("text") if isinstance(data.get("text"), str) else content_text(data.get("content"))
                text = prompt_text(text)
                if text:
                    label = "prompt" if state["prompted"] else "delegation"
                    state["prompted"] = True
                    clipped, lines, truncated = clip(text, TEXT_MAX_CHARS)
                    self._emit(dict(base, id="oc:%s:%s" % (sid[-8:], mid), kind="prompt",
                                    text=clipped, role=label, lines=lines, truncated=truncated))
                continue
            if mtype == "idle":
                if "idle" not in seen["items"]:
                    seen["items"].add("idle")
                    outcome = str(data.get("outcome") or "idle")
                    self._emit(dict(base, id="oc:%s:%s" % (sid[-8:], mid), kind="status",
                                    text="Session idle · " + outcome))
                    if not state.get("root"):
                        self.sources.get("oc:" + sid, {})["finished"] = True
                continue
            if mtype != "assistant":
                continue
            items = data.get("content") if isinstance(data.get("content"), list) else []
            complete = bool(mtime.get("completed"))
            for index, item in enumerate(items):
                if not isinstance(item, dict):
                    continue
                key = "oc:%s:%s:%d" % (sid[-8:], mid, index)
                itype = item.get("type")
                final = complete or index < len(items) - 1
                item_ts = ts
                if isinstance(item.get("time"), dict) and item["time"].get("created"):
                    item_ts = iso_ms(item["time"]["created"]) or ts
                if itype in ("reasoning", "text"):
                    if index in seen["items"] or not final:
                        continue
                    seen["items"].add(index)
                    text, _, truncated = clip(item.get("text") or "", TEXT_MAX_CHARS)
                    if text.strip():
                        self._emit(dict(base, ts=item_ts, id=key,
                                        kind="thinking" if itype == "reasoning" else "text",
                                        text=text.strip(), truncated=truncated))
                elif itype == "tool":
                    tool_state = item.get("state") if isinstance(item.get("state"), dict) else {}
                    status = tool_state.get("status")
                    data_in = tool_state.get("input") if isinstance(tool_state.get("input"), dict) else {}
                    call = str(item.get("id") or key)
                    name = str(item.get("name") or item.get("tool") or "tool")
                    if index not in seen["items"] and (data_in or status in ("completed", "error")):
                        seen["items"].add(index)
                        shown, _, _ = clip(json.dumps(data_in, indent=2, ensure_ascii=False), INPUT_MAX_CHARS)
                        title, _, _ = clip(tool_title(name, data_in, self.root), INPUT_MAX_CHARS)
                        self._emit(dict(base, ts=item_ts, id=key, kind="tool", tool=tool_display_name(name),
                                        title=title, input=shown, diff=tool_diff(name, data_in), callId=call))
                    if status in ("completed", "error") and index not in seen["results"]:
                        seen["results"].add(index)
                        text = content_text(tool_state.get("content"))
                        if not text and isinstance(tool_state.get("output"), str):
                            text = tool_state["output"]
                        if status == "error" and tool_state.get("error"):
                            text = (text + "\n" if text else "") + str(tool_state.get("error"))
                        output, lines, truncated = clip(text, OUTPUT_MAX_CHARS, OUTPUT_MAX_LINES)
                        self._emit(dict(base, ts=item_ts, id=key + ":result", kind="result", callId=call,
                                        tool=tool_display_name(name), output=output, lines=lines,
                                        truncated=truncated, error=status == "error"))


def now_minus(at):
    return time.time() - at if at else float("inf")


def file_mentions(path, needle):
    """True when the file contains needle. Reads in chunks with overlap."""
    target = needle.encode("utf-8")
    if not target:
        return False
    tail = b""
    try:
        with open(path, "rb") as fh:
            while True:
                chunk = fh.read(1 << 20)
                if not chunk:
                    return False
                if target in tail + chunk:
                    return True
                tail = chunk[-len(target):]
    except OSError:
        return False


def load_template(kit_root):
    candidates = []
    if kit_root:
        candidates.append(os.path.join(kit_root, ".agent-stack", "templates",
                                       "watch", "watch.html"))
    here = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(here, "..", ".agent-stack", "templates",
                                   "watch", "watch.html"))
    for path in candidates:
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            # Embed the pre-rendered CC0 atlas: the viewer makes no asset requests.
            # Missing art is nonfatal; the UI falls back to labeled initials.
            atlas_path = os.path.join(os.path.dirname(path), "characters.json")
            atlas = None
            try:
                with open(atlas_path, encoding="utf-8") as fh:
                    atlas = json.load(fh)
            except (OSError, ValueError):
                pass
            office_path = os.path.join(os.path.dirname(path), "office.js")
            office = ""
            try:
                with open(office_path, encoding="utf-8") as fh:
                    office = fh.read()
            except OSError:
                pass
            return text.replace("__ASTACK_CHARACTERS__",
                                json.dumps(atlas).replace("<", "\\u003c")) \
                .replace("__ASTACK_OFFICE__", office)
    return None


def make_handler(root, pinned_run_id, template_text, harness_override=None,
                 transcripts=True, claude_dir=None, opencode_db=None):
    config_file = os.path.join(root, ".agent-stack", "config.conf")
    indexes = {}
    indexes_lock = threading.Lock()

    def transcript_index(run_id):
        with indexes_lock:
            index = indexes.get(run_id)
            if index is None:
                index = indexes[run_id] = TranscriptIndex(root, run_id, claude_dir, opencode_db)
            return index

    class Handler(BaseHTTPRequestHandler):
        server_version = "astack-watch/1"

        def log_message(self, fmt, *args):  # keep demo output clean
            sys.stderr.write("watch: %s\n" % (fmt % args))

        def _send_json(self, status, obj):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send_html(self, status, text):
            body = text.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _resolve_run(self, query):
            """Pick the run for this request.

            Returns (run_id, error_status, error_obj). Explicit ?run=
            wins, then the pinned run, then the latest run.
            """
            requested = query.get("run", [None])[0]
            if requested:
                err = check_run_id(requested)
                if err:
                    return None, 400, {"error": err}
                if not os.path.isdir(run_dir(root, requested)):
                    return None, 404, {"error": "no such run: %s" % requested}
                return requested, None, None
            if pinned_run_id:
                if not os.path.isdir(run_dir(root, pinned_run_id)):
                    return None, 404, {"error": "no such run: %s" % pinned_run_id}
                return pinned_run_id, None, None
            runs = list_runs(root)
            if not runs:
                return None, 404, {"error": "no runs yet — start a delivery run "
                                            "and this view follows it"}
            return runs[0]["runId"], None, None

        def do_GET(self):  # noqa: N802 (stdlib handler naming)
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            if parsed.path in ("/", "/index.html"):
                if template_text is None:
                    self._send_json(500, {"error": "watch template missing"})
                    return
                page = template_text.replace("__ASTACK_RUN__",
                                             pinned_run_id or "latest")
                self._send_html(200, page)
                return
            if parsed.path == "/api/runs":
                self._send_json(200, {"runs": list_runs(root)})
                return
            if parsed.path == "/api/state":
                run_id, err_status, err_obj = self._resolve_run(query)
                if err_status:
                    self._send_json(err_status, err_obj)
                    return
                try:
                    with open(os.path.join(run_dir(root, run_id),
                                           "state.json"),
                              encoding="utf-8") as fh:
                        state = json.load(fh)
                except (OSError, ValueError) as exc:
                    self._send_json(500, {"error": "cannot read state: %s" % exc})
                    return
                self._send_json(200, state)
                return
            if parsed.path == "/api/events":
                run_id, err_status, err_obj = self._resolve_run(query)
                if err_status:
                    self._send_json(err_status, err_obj)
                    return
                try:
                    since = int(query.get("since", ["0"])[0])
                except ValueError:
                    since = 0
                if since < 0:
                    since = 0
                events = []
                total = since
                events_file = os.path.join(run_dir(root, run_id), "events.jsonl")
                if os.path.isfile(events_file):
                    try:
                        with open(events_file, encoding="utf-8") as fh:
                            lines = fh.readlines()
                    except OSError as exc:
                        self._send_json(500, {"error": "cannot read events: %s" % exc})
                        return
                    total = len(lines)
                    for offset in range(since, total):
                        text = lines[offset].strip()
                        if not text:
                            continue
                        try:
                            entry = json.loads(text)
                        except ValueError:
                            entry = {"raw": text, "parseError": True}
                        entry["_offset"] = offset
                        events.append(entry)
                self._send_json(200, {"runId": run_id, "events": events,
                                      "nextOffset": total})
                return
            if parsed.path == "/api/transcript":
                run_id, err_status, err_obj = self._resolve_run(query)
                if err_status:
                    self._send_json(err_status, err_obj)
                    return
                try:
                    since = max(0, int(query.get("since", ["0"])[0]))
                except ValueError:
                    since = 0
                if not transcripts:
                    self._send_json(200, {"runId": run_id, "enabled": False, "entries": [],
                                          "nextSeq": 0, "sources": [], "errors": []})
                    return
                index = transcript_index(run_id)
                index.refresh()
                body = index.snapshot(since)
                body.update(runId=run_id, enabled=True)
                self._send_json(200, body)
                return
            if parsed.path == "/api/meta":
                config = read_config(config_file)
                models = {}
                for role, model_key, variant_key in ROLE_MODEL_KEYS:
                    models[role] = {
                        "model": config.get(model_key, ""),
                        "variant": config.get(variant_key, ""),
                    }
                if pinned_run_id:
                    run_id = pinned_run_id
                else:
                    requested = query.get("run", [None])[0]
                    if requested and not check_run_id(requested) and \
                            os.path.isdir(run_dir(root, requested)):
                        run_id = requested
                    else:
                        runs = list_runs(root)
                        run_id = runs[0]["runId"] if runs else None
                harness = detect_harness(root, config)
                if harness_override:
                    harness = {
                        "name": harness_override,
                        "platforms": harness["platforms"],
                        "version": harness["version"],
                        "source": "Viewer option",
                    }
                meta = {
                    "mode": "pinned" if pinned_run_id else "follow",
                    "runId": run_id,
                    "harness": harness,
                    "models": models,
                    "jev": {
                        "provider": config.get("JEV_PROVIDER", "none"),
                        "model": config.get("JEV_MODEL", "jev-latest"),
                    },
                }
                if run_id:
                    state_file = os.path.join(run_dir(root, run_id), "state.json")
                    if os.path.isfile(state_file):
                        try:
                            with open(state_file, encoding="utf-8") as fh:
                                state = json.load(fh)
                            meta["phase"] = state.get("phase")
                            meta["changeId"] = state.get("changeId")
                            meta["issueId"] = state.get("issueId")
                            budget = state.get("budget", {})
                            meta["correctiveRoundsRemaining"] = budget.get(
                                "correctiveRoundsRemaining")
                        except (OSError, ValueError):
                            pass
                self._send_json(200, meta)
                return
            self._send_json(404, {"error": "not found"})

        def do_POST(self):  # read-only: refuse everything else
            self._send_json(405, {"error": "watch is read-only"})

        def do_PUT(self):
            self._send_json(405, {"error": "watch is read-only"})

        def do_DELETE(self):
            self._send_json(405, {"error": "watch is read-only"})

        def do_PATCH(self):
            self._send_json(405, {"error": "watch is read-only"})

    return Handler


def build_parser():
    parser = argparse.ArgumentParser(description="Read-only Agent Stack run watcher")
    parser.add_argument("--root", default=".",
                        help="Target project root (default: current directory)")
    parser.add_argument("--run", default=None,
                        help="Run ID to pin to; omit to follow the latest run")
    parser.add_argument("--kit-root", default=None,
                        help="Kit checkout (for the viewer template)")
    parser.add_argument("--host", default="127.0.0.1",
                        help="Bind address (default: 127.0.0.1)")
    parser.add_argument("--harness", default=None,
                        help="Host name to display (default: detect installed "
                             "platform markers in the project)")
    parser.add_argument("--port", type=int, default=4311,
                        help="Port to serve on; 0 picks an ephemeral port")
    parser.add_argument("--no-transcripts", dest="transcripts", action="store_false",
                        help="Do not read the harness's local session transcripts; "
                             "show only telemetry the agents emitted")
    parser.add_argument("--claude-projects", default=None, help=argparse.SUPPRESS)
    parser.add_argument("--opencode-db", default=None, help=argparse.SUPPRESS)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--open", dest="open_browser", action="store_true",
                       help="Open the viewer in the default browser")
    group.add_argument("--no-open", dest="open_browser", action="store_false",
                       help="Do not open a browser (default when piped)")
    parser.set_defaults(open_browser=None)
    return parser


def main():
    args = build_parser().parse_args()
    if args.run:
        err = check_run_id(args.run)
        if err:
            print("watch: %s" % err, file=sys.stderr)
            sys.exit(2)
    root = os.path.abspath(args.root)
    kit_root = (os.path.abspath(args.kit_root) if args.kit_root
                else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    if args.run and not os.path.isdir(run_dir(root, args.run)):
        print("watch: no such run: %s (expected %s)"
              % (args.run, run_dir(root, args.run)), file=sys.stderr)
        sys.exit(1)
    template_text = load_template(kit_root)
    if template_text is None:
        print("watch: viewer template missing (.agent-stack/templates/watch/watch.html)",
              file=sys.stderr)
        sys.exit(1)
    handler = make_handler(root, args.run, template_text, args.harness,
                           transcripts=args.transcripts, claude_dir=args.claude_projects,
                           opencode_db=args.opencode_db)
    server = ThreadingHTTPServer((args.host, args.port), handler)
    actual_port = server.server_address[1]
    url = "http://%s:%d/" % (args.host, actual_port)
    if args.run:
        print("watching run %s at %s (read-only; Ctrl-C to stop)"
              % (args.run, url))
    else:
        print("watching latest run at %s (read-only; Ctrl-C to stop) — "
              "start a run and this view follows it; use --run ID to pin one run"
              % url)
    sys.stdout.flush()
    should_open = args.open_browser
    if should_open is None:
        should_open = sys.stdout.isatty()
    if should_open:
        try:
            import webbrowser
            webbrowser.open(url)
        except Exception as exc:  # browser is best-effort; server still runs
            print("watch: could not open a browser (%s); visit %s" % (exc, url),
                  file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
