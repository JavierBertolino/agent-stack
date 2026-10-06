#!/usr/bin/env python3
"""watch.py — read-only live teaching overlay for Agent Stack delivery runs.

Serves one self-contained viewer page plus JSON APIs backed by
.agent-stack/runs/<run-id>/state.json and append-only events.jsonl.
Read-only: only GET is implemented; the server never writes to the run.

Usage:
  watch.py --run <run-id> [--root PATH] [--kit-root PATH]
           [--host 127.0.0.1] [--port 4311] [--open | --no-open]

Endpoints:
  GET /                    Viewer page (template from
                           .agent-stack/templates/watch/watch.html)
  GET /api/state           Run state.json (404 when the run is unknown)
  GET /api/events?since=N  Events after line offset N as
                           {"events": [...], "nextOffset": M}
  GET /api/meta            Resolved OpenCode models + Jev routing from the
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


def make_handler(root, run_id, template_text):
    state_file = os.path.join(run_dir(root, run_id), "state.json")
    events_file = os.path.join(run_dir(root, run_id), "events.jsonl")
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

        def do_GET(self):  # noqa: N802 (stdlib handler naming)
            parsed = urlparse(self.path)
            if parsed.path in ("/", "/index.html"):
                if template_text is None:
                    self._send_json(500, {"error": "watch template missing"})
                    return
                page = template_text.replace("__ASTACK_RUN__", run_id)
                self._send_html(200, page)
                return
            if parsed.path == "/api/state":
                if not os.path.isfile(state_file):
                    self._send_json(404, {"error": "no such run: %s" % run_id})
                    return
                try:
                    with open(state_file, encoding="utf-8") as fh:
                        state = json.load(fh)
                except (OSError, ValueError) as exc:
                    self._send_json(500, {"error": "cannot read state: %s" % exc})
                    return
                self._send_json(200, state)
                return
            if parsed.path == "/api/events":
                query = parse_qs(parsed.query)
                try:
                    since = int(query.get("since", ["0"])[0])
                except ValueError:
                    since = 0
                if since < 0:
                    since = 0
                events = []
                total = since
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
                self._send_json(200, {"events": events, "nextOffset": total})
                return
            if parsed.path == "/api/meta":
                config = read_config(config_file)
                models = {}
                for role, model_key, variant_key in ROLE_MODEL_KEYS:
                    models[role] = {
                        "model": config.get(model_key, ""),
                        "variant": config.get(variant_key, ""),
                    }
                meta = {
                    "runId": run_id,
                    "models": models,
                    "jev": {
                        "provider": config.get("JEV_PROVIDER", "none"),
                        "model": config.get("JEV_MODEL", "jev-latest"),
                    },
                }
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
    parser.add_argument("--run", required=True, help="Run ID to watch")
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
    if not RUN_ID_RE.match(args.run):
        print("watch: invalid run id %r (use [A-Za-z0-9._-])" % args.run,
              file=sys.stderr)
        sys.exit(2)
    root = os.path.abspath(args.root)
    kit_root = (os.path.abspath(args.kit_root) if args.kit_root
                else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    if not os.path.isdir(run_dir(root, args.run)):
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
    print("watching run %s at %s (read-only; Ctrl-C to stop)" % (args.run, url))
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
