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

Stdlib only.
"""

import argparse
import json
import os
import re
import sys
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
            values[key.strip()] = value.strip()
    return values


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
                return fh.read()
    return None


def make_handler(root, pinned_run_id, template_text):
    config_file = os.path.join(root, ".agent-stack", "config.conf")

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
                meta = {
                    "mode": "pinned" if pinned_run_id else "follow",
                    "runId": run_id,
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
    parser.add_argument("--port", type=int, default=4311,
                        help="Port to serve on; 0 picks an ephemeral port")
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
    handler = make_handler(root, args.run, template_text)
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
