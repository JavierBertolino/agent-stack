#!/usr/bin/env python3
"""run-state.py — validated run state for Agent Stack delivery runs.

The resolver is the sole writer. State lives at
.agent-stack/runs/<run-id>/state.json with append-only events.jsonl beside
it. All transitions are validated; external side effects (issue updates,
PR IDs) are recorded immediately so retries resume instead of duplicating.

Usage:
  run-state.py --root PATH <command> [options]

Commands:
  init             Create a run (fails if it already exists)
  event            Append an event (transition/evidence/external/verify/...)
  transition       Move to a new phase (validated against the allowed graph)
  record-external  Record an external side effect (specPr, implPr, issueState, ...)
  record-artifact  Record an artifact path + hash
  record-code      Record the current code hash (marks verification stale on change)
  record-verify    Record a verification result against a code hash
  resume           Print a resume summary (phase, external IDs, staleness, next action)
  validate         Validate state.json + events.jsonl against the contracts
  lock / unlock    Cooperative run lock (prevents concurrent duplicate delivery)
"""

import argparse
import datetime
import json
import os
import sys

SCHEMA_VERSION = "1"

TRANSITIONS = {
    "intake": {"preflight", "blocked", "dropped"},
    "preflight": {"clarify", "blocked", "dropped"},
    "clarify": {"branch", "blocked", "dropped"},
    "branch": {"specify", "blocked", "dropped"},
    "specify": {"publish-spec", "implement", "blocked", "dropped"},
    "publish-spec": {"implement", "blocked", "dropped"},
    "implement": {"review", "blocked", "dropped"},
    "review": {"qa", "implement", "close", "blocked", "dropped"},
    "qa": {"close", "implement", "blocked", "dropped"},
    "close": {"awaiting_merge", "blocked"},
    "awaiting_merge": set(),
    "blocked": {"preflight", "clarify", "branch", "specify", "implement",
                "review", "qa", "dropped"},
    "dropped": set(),
}

TERMINAL = {"awaiting_merge", "dropped"}


def utcnow():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def run_dir(root, run_id):
    return os.path.join(root, ".agent-stack", "runs", run_id)


def state_path(root, run_id):
    return os.path.join(run_dir(root, run_id), "state.json")


def events_path(root, run_id):
    return os.path.join(run_dir(root, run_id), "events.jsonl")


def lock_path(root, run_id):
    return os.path.join(root, ".agent-stack", "runs", run_id + ".lock")


def die(msg):
    print("run-state.py: %s" % msg, file=sys.stderr)
    sys.exit(1)


def load_state(root, run_id):
    path = state_path(root, run_id)
    if not os.path.isfile(path):
        die("no such run: %s" % run_id)
    with open(path) as fh:
        return json.load(fh)


def save_state(root, run_id, state):
    state["updatedAt"] = utcnow()
    path = state_path(root, run_id)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


def append_event(root, run_id, type_, phase, detail):
    entry = {"ts": utcnow(), "runId": run_id, "type": type_,
             "phase": phase, "detail": detail}
    with open(events_path(root, run_id), "a") as fh:
        fh.write(json.dumps(entry, sort_keys=True) + "\n")


def cmd_init(args):
    directory = run_dir(args.root, args.run)
    if os.path.exists(state_path(args.root, args.run)):
        die("run already exists: %s (resume it instead of re-creating)" % args.run)
    os.makedirs(os.path.join(directory, "evidence"), exist_ok=True)
    state = {
        "schemaVersion": SCHEMA_VERSION,
        "runId": args.run,
        "issueId": args.issue,
        "changeId": args.change,
        "phase": "intake",
        "correctiveRoundsUsed": 0,
        "maxCorrectiveRounds": args.max_rounds,
        "worktree": {
            "root": args.worktree_root or "",
            "repositoryId": args.repo or "",
            "baseRef": args.base_ref or "",
            "baseSha": args.base_sha or "",
            "branch": args.branch,
            "allowedScope": args.scope or [],
        },
        "artifacts": [],
        "governance": {"sources": [], "gaps": []},
        "skills": [],
        "verification": {"plan": [], "history": [], "lastCodeHash": None,
                         "lastVerifiedHash": None, "stale": False},
        "external": {"issueUrl": None, "issueState": None, "specPr": None,
                     "specBranch": None, "implPrs": []},
        "budget": {"correctiveRoundsRemaining": args.max_rounds,
                   "timeboxMinutes": args.timebox},
        "nextAction": "preflight",
        "updatedAt": utcnow(),
    }
    save_state(args.root, args.run, state)
    append_event(args.root, args.run, "init", "intake",
                 "run created for change %s (issue %s)" % (args.change, args.issue))
    print("initialized run %s" % args.run)


def cmd_event(args):
    state = load_state(args.root, args.run)
    append_event(args.root, args.run, args.type, state["phase"], args.detail)
    save_state(args.root, args.run, state)
    print("event recorded")


def cmd_transition(args):
    state = load_state(args.root, args.run)
    current = state["phase"]
    if args.to not in TRANSITIONS.get(current, set()):
        die("invalid transition %s -> %s (allowed: %s)"
            % (current, args.to, sorted(TRANSITIONS.get(current, set()))))
    if current in TERMINAL:
        die("run is terminal (%s); start a new run instead" % current)
    state["phase"] = args.to
    if args.to in ("implement", "review", "qa") and args.corrective:
        state["correctiveRoundsUsed"] += 1
        state["budget"]["correctiveRoundsRemaining"] = max(
            0, state["maxCorrectiveRounds"] - state["correctiveRoundsUsed"])
    state["nextAction"] = args.next or args.to
    save_state(args.root, args.run, state)
    append_event(args.root, args.run, "transition", args.to,
                 "%s -> %s%s" % (current, args.to,
                                 ("; " + args.detail) if args.detail else ""))
    remaining = state["budget"]["correctiveRoundsRemaining"]
    print("transitioned to %s (corrective rounds remaining: %d)" % (args.to, remaining))
    if remaining == 0 and args.to not in TERMINAL:
        print("warning: corrective budget exhausted; next failure blocks the run",
              file=sys.stderr)


def cmd_record_external(args):
    state = load_state(args.root, args.run)
    ext = state["external"]
    if args.key == "implPr":
        if args.value not in ext["implPrs"]:
            ext["implPrs"].append(args.value)
    elif args.key in ("specPr", "specBranch", "issueState", "issueUrl"):
        ext[args.key] = args.value
    else:
        die("unknown external key: %s (specPr|specBranch|implPr|issueState|issueUrl)"
            % args.key)
    state["nextAction"] = state["phase"]
    save_state(args.root, args.run, state)
    append_event(args.root, args.run, "external", state["phase"],
                 "%s=%s" % (args.key, args.value))
    print("recorded external %s=%s (reuse on retry; never duplicate)" % (args.key, args.value))


def cmd_record_artifact(args):
    state = load_state(args.root, args.run)
    state["artifacts"] = [a for a in state["artifacts"] if a["path"] != args.path]
    state["artifacts"].append({"path": args.path, "sha256": args.sha256})
    save_state(args.root, args.run, state)
    append_event(args.root, args.run, "evidence", state["phase"],
                 "artifact %s sha256=%s" % (args.path, args.sha256))
    print("recorded artifact %s" % args.path)


def cmd_record_code(args):
    state = load_state(args.root, args.run)
    verification = state["verification"]
    previous = verification["lastCodeHash"]
    verification["lastCodeHash"] = args.code_hash
    if previous is not None and previous != args.code_hash:
        verification["stale"] = True
        append_event(args.root, args.run, "code", state["phase"],
                     "code hash changed %s -> %s; prior verification is stale"
                     % (previous, args.code_hash))
        print("code changed; verification marked stale (re-verify before PASS)")
    else:
        append_event(args.root, args.run, "code", state["phase"],
                     "code hash %s" % args.code_hash)
        print("recorded code hash")
    save_state(args.root, args.run, state)


def cmd_record_verify(args):
    state = load_state(args.root, args.run)
    verification = state["verification"]
    if verification["lastCodeHash"] != args.code_hash:
        die("verify hash %s does not match recorded code hash %s; "
            "record-code first" % (args.code_hash, verification["lastCodeHash"]))
    verification["history"].append({
        "command": args.command, "workdir": args.workdir or "",
        "result": args.result, "codeHash": args.code_hash})
    verification["lastVerifiedHash"] = args.code_hash
    verification["stale"] = False
    save_state(args.root, args.run, state)
    append_event(args.root, args.run, "verify", state["phase"],
                 "%s -> %s (code %s)" % (args.command, args.result, args.code_hash))
    print("recorded verification (stale=false)")


def cmd_resume(args):
    state = load_state(args.root, args.run)
    verification = state["verification"]
    ext = state["external"]
    lines = [
        "run: %s (change %s, issue %s)" % (state["runId"], state["changeId"], state["issueId"]),
        "phase: %s" % state["phase"],
        "corrective rounds: %d used / %d max" % (
            state["correctiveRoundsUsed"], state["maxCorrectiveRounds"]),
        "spec PR: %s" % (ext["specPr"] or "none"),
        "spec branch: %s" % (ext["specBranch"] or "none"),
        "implementation PRs: %s" % (", ".join(ext["implPrs"]) or "none"),
        "issue state: %s" % (ext["issueState"] or "unknown (re-read before updating)"),
        "verification stale: %s" % verification["stale"],
        "next action: %s" % (state["nextAction"] or state["phase"]),
    ]
    if verification["stale"]:
        lines.append("BLOCKED: code changed since last verification; re-run the "
                     "verification plan before accepting any PASS.")
    print("\n".join(lines))


def _load_schema(kit_root, name):
    path = os.path.join(kit_root, ".agent-stack", "contracts", name)
    with open(path) as fh:
        return json.load(fh)


def _check(schema, value, where):
    """Minimal JSON-Schema subset: type (incl. lists), required, properties,
    items, enum, const, minLength, minItems, minimum."""
    errors = []
    stype = schema.get("type")
    if stype is not None:
        types = stype if isinstance(stype, list) else [stype]
        ok = False
        for t in types:
            if t == "string" and isinstance(value, str):
                ok = True
            elif t == "integer" and isinstance(value, int) and not isinstance(value, bool):
                ok = True
            elif t == "boolean" and isinstance(value, bool):
                ok = True
            elif t == "null" and value is None:
                ok = True
            elif t == "array" and isinstance(value, list):
                ok = True
            elif t == "object" and isinstance(value, dict):
                ok = True
        if not ok:
            return ["%s: expected %s, got %s" % (where, types, type(value).__name__)]
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append("%s: missing required field %r" % (where, key))
        for key, subschema in schema.get("properties", {}).items():
            if key in value:
                errors += _check(subschema, value[key], "%s.%s" % (where, key))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append("%s: need >= %d items" % (where, schema["minItems"]))
        for i, item in enumerate(value):
            errors += _check(schema.get("items", {}), item, "%s[%d]" % (where, i))
    if isinstance(value, str) and "minLength" in schema:
        if len(value) < schema["minLength"]:
            errors.append("%s: too short" % where)
    if isinstance(value, (int, float)) and "minimum" in schema:
        if value < schema["minimum"]:
            errors.append("%s: below minimum" % where)
    if "enum" in schema and value not in schema["enum"]:
        errors.append("%s: %r not in %s" % (where, value, schema["enum"]))
    if "const" in schema and value != schema["const"]:
        errors.append("%s: expected const %r" % (where, schema["const"]))
    return errors


def cmd_validate(args):
    kit_root = args.kit_root or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..")
    state = load_state(args.root, args.run)
    schema = _load_schema(kit_root, "run-state.schema.json")
    errors = _check(schema, state, "state.json")
    if state["phase"] not in TRANSITIONS:
        errors.append("state.json: unknown phase %r" % state["phase"])
    if state["verification"]["stale"] and state["phase"] in ("close", "awaiting_merge"):
        errors.append("state.json: stale verification in phase %s" % state["phase"])
    ev_schema = _load_schema(kit_root, "event.schema.json")
    events_file = events_path(args.root, args.run)
    if not os.path.isfile(events_file):
        errors.append("events.jsonl: missing")
    else:
        with open(events_file) as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError as exc:
                    errors.append("events.jsonl:%d: invalid JSON (%s)" % (lineno, exc))
                    continue
                errors += _check(ev_schema, entry, "events.jsonl:%d" % lineno)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    print("run %s valid (%s)" % (args.run, state["phase"]))


def cmd_lock(args):
    path = lock_path(args.root, args.run)
    try:
        os.makedirs(path)
    except FileExistsError:
        holder = "unknown"
        info = os.path.join(path, "holder")
        if os.path.isfile(info):
            with open(info) as fh:
                holder = fh.read().strip()
        die("run %s is locked by %s" % (args.run, holder))
    with open(os.path.join(path, "holder"), "w") as fh:
        fh.write(args.holder or "unknown")
    print("locked run %s" % args.run)


def cmd_unlock(args):
    path = lock_path(args.root, args.run)
    info = os.path.join(path, "holder")
    if os.path.isdir(path):
        if os.path.isfile(info):
            os.remove(info)
        os.rmdir(path)
        print("unlocked run %s" % args.run)
    else:
        print("run %s was not locked" % args.run)


def build_parser():
    parser = argparse.ArgumentParser(description="Validated Agent Stack run state")
    parser.add_argument("--root", default=".", help="Target project root")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init")
    p.add_argument("--run", required=True)
    p.add_argument("--issue", default=None)
    p.add_argument("--change", required=True)
    p.add_argument("--max-rounds", type=int, default=3)
    p.add_argument("--timebox", type=int, default=25)
    p.add_argument("--worktree-root", default=None)
    p.add_argument("--repo", default=None)
    p.add_argument("--base-ref", default=None)
    p.add_argument("--base-sha", default=None)
    p.add_argument("--branch", default=None)
    p.add_argument("--scope", action="append", default=None)
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("event")
    p.add_argument("--run", required=True)
    p.add_argument("--type", required=True,
                   choices=["init", "transition", "evidence", "external", "verify",
                            "code", "lock", "note", "budget", "close"])
    p.add_argument("--detail", required=True)
    p.set_defaults(func=cmd_event)

    p = sub.add_parser("transition")
    p.add_argument("--run", required=True)
    p.add_argument("--to", required=True)
    p.add_argument("--detail", default="")
    p.add_argument("--next", default=None)
    p.add_argument("--corrective", action="store_true",
                   help="Count this move as a corrective round")
    p.set_defaults(func=cmd_transition)

    p = sub.add_parser("record-external")
    p.add_argument("--run", required=True)
    p.add_argument("--key", required=True,
                   choices=["specPr", "specBranch", "implPr", "issueState", "issueUrl"])
    p.add_argument("--value", required=True)
    p.set_defaults(func=cmd_record_external)

    p = sub.add_parser("record-artifact")
    p.add_argument("--run", required=True)
    p.add_argument("--path", required=True)
    p.add_argument("--sha256", required=True)
    p.set_defaults(func=cmd_record_artifact)

    p = sub.add_parser("record-code")
    p.add_argument("--run", required=True)
    p.add_argument("--code-hash", required=True)
    p.set_defaults(func=cmd_record_code)

    p = sub.add_parser("record-verify")
    p.add_argument("--run", required=True)
    p.add_argument("--command", required=True)
    p.add_argument("--workdir", default="")
    p.add_argument("--result", required=True)
    p.add_argument("--code-hash", required=True)
    p.set_defaults(func=cmd_record_verify)

    p = sub.add_parser("resume")
    p.add_argument("--run", required=True)
    p.set_defaults(func=cmd_resume)

    p = sub.add_parser("validate")
    p.add_argument("--run", required=True)
    p.add_argument("--kit-root", default=None, help="Kit checkout (for schemas)")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("lock")
    p.add_argument("--run", required=True)
    p.add_argument("--holder", default=None)
    p.set_defaults(func=cmd_lock)

    p = sub.add_parser("unlock")
    p.add_argument("--run", required=True)
    p.set_defaults(func=cmd_unlock)

    return parser


def main():
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
