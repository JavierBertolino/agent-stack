#!/usr/bin/env sh
# Watch-mode tests: new telemetry event types validate, append to a run,
# and are served read-only by scripts/watch.py alongside state and models.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0

T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-watch.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM

# 1. One of each telemetry type validates against event.schema.json.
cat > "$T/telemetry-valid.jsonl" <<'EOF'
{"detail": "{\"agent\":\"resolver\",\"model\":\"harness default\"}", "phase": "preflight", "runId": "watch-1", "ts": "2026-09-08T00:00:00+00:00", "type": "agent-start"}
{"detail": "{\"agent\":\"developer\",\"model\":\"example/model\"}", "phase": "implement", "runId": "watch-1", "ts": "2026-09-08T00:01:00+00:00", "type": "agent-start"}
{"detail": "{\"contractVersion\":\"1\"}", "phase": "implement", "runId": "watch-1", "ts": "2026-09-08T00:02:00+00:00", "type": "handoff"}
{"detail": "{\"contractVersion\":\"1\"}", "phase": "implement", "runId": "watch-1", "ts": "2026-09-08T00:03:00+00:00", "type": "report"}
{"detail": "{\"model\":\"jev-latest\",\"state\":{},\"questions\":{\"ok\":{\"type\":\"noul\",\"instructions\":\"Is this valid?\"}}}", "phase": "qa", "runId": "watch-1", "ts": "2026-09-08T00:04:00+00:00", "type": "jev-request"}
{"detail": "{\"ok\":{\"answer\":true}}", "phase": "qa", "runId": "watch-1", "ts": "2026-09-08T00:05:00+00:00", "type": "jev-response"}
{"detail": "{\"agent\":\"developer\",\"model\":\"example/model\",\"input\":1200,\"output\":600,\"total\":1800,\"source\":\"self-reported\"}", "phase": "implement", "runId": "watch-1", "ts": "2026-09-08T00:06:00+00:00", "type": "usage"}
{"detail": "{\"agent\":\"developer\",\"status\":\"done\"}", "phase": "implement", "runId": "watch-1", "ts": "2026-09-08T00:07:00+00:00", "type": "agent-end"}
EOF
if ! python3 "$KIT_ROOT/scripts/validate-contracts.py" --kit-root "$KIT_ROOT" \
  --type event "$T/telemetry-valid.jsonl" >/dev/null 2>&1; then
  printf 'FAIL watch telemetry fixtures should validate\n' >&2; FAIL=1
fi

# 2. Telemetry appends to a real run and the run still validates.
R="$T/project"
mkdir -p "$R"
python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" init --run watch-1 \
  --change demo-change --worktree-root "$R/.worktrees/demo" --repo demo \
  --base-ref main --base-sha abc123 --scope src >/dev/null 2>&1 \
  || { printf 'FAIL run init\n' >&2; FAIL=1; }
for pair in "agent-start {\"agent\":\"resolver\"}" "handoff {\"contractVersion\":\"1\"}" \
  "jev-request {\"model\":\"jev-latest\"}" "jev-response {}" \
  "usage {\"agent\":\"resolver\",\"input\":10,\"output\":5,\"total\":15,\"source\":\"self-reported\"}" \
  "agent-end {\"agent\":\"resolver\"}"; do
  type=${pair%% *}
  detail=${pair#* }
  if ! python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" event \
    --run watch-1 --type "$type" --detail "$detail" >/dev/null 2>&1; then
    printf 'FAIL event append %s\n' "$type" >&2; FAIL=1
  fi
done
if ! python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" validate \
  --run watch-1 --kit-root "$KIT_ROOT" >/dev/null 2>&1; then
  printf 'FAIL run with telemetry should validate\n' >&2; FAIL=1
fi

# 3. Unknown event types are still rejected.
if python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" event \
  --run watch-1 --type bogus-type --detail '{}' >/dev/null 2>&1; then
  printf 'FAIL unknown event type should be rejected\n' >&2; FAIL=1
fi

# 4. Watch server: HTML page plus read-only JSON APIs.
[ -f "$KIT_ROOT/.agent-stack/templates/watch/watch.html" ] \
  || { printf 'FAIL watch template missing\n' >&2; FAIL=1; }
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 "$KIT_ROOT/scripts/watch.py" --root "$R" --kit-root "$KIT_ROOT" \
  --run watch-1 --host 127.0.0.1 --port "$PORT" --no-open \
  >"$T/watch.log" 2>&1 &
SERVER_PID=$!
READY=0
i=0
while [ "$i" -lt 50 ]; do
  if python3 - "$PORT" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
port = sys.argv[1]
with urllib.request.urlopen("http://127.0.0.1:%s/api/state" % port, timeout=2) as r:
    json.load(r)
PY
  then READY=1; break
  fi
  sleep 0.1
  i=$((i + 1))
done
if [ "$READY" != 1 ]; then
  printf 'FAIL watch server did not start\n' >&2
  sed 's/^/  watch.log: /' "$T/watch.log" >&2 || true
  FAIL=1
else
  if ! python3 - "$PORT" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
port = sys.argv[1]
def get(path):
    with urllib.request.urlopen("http://127.0.0.1:%s%s" % (port, path), timeout=2) as r:
        return r.status, r.read()
status, body = get("/api/events?since=0")
data = json.loads(body)
assert status == 200 and data["nextOffset"] >= 7, data
types = {e.get("type") for e in data["events"]}
assert {"agent-start", "handoff", "usage", "agent-end"} <= types, types
status, body = get("/api/meta")
meta = json.loads(body)
assert status == 200 and meta["runId"] == "watch-1", meta
assert "models" in meta and "jev" in meta, meta
status, body = get("/")
assert status == 200 and b"watch-1" in body, status
PY
  then printf 'FAIL watch APIs did not serve state/events/meta/page\n' >&2; FAIL=1
  fi
  if python3 - "$PORT" <<'PY' >/dev/null 2>&1
import sys, urllib.request, urllib.error
port = sys.argv[1]
req = urllib.request.Request("http://127.0.0.1:%s/api/events" % port,
                             data=b"{}", method="POST")
try:
    urllib.request.urlopen(req, timeout=2)
except urllib.error.HTTPError as e:
    sys.exit(0 if e.code == 405 else 1)
sys.exit(1)
PY
  then :
  else printf 'FAIL watch must refuse POST with 405\n' >&2; FAIL=1
  fi
fi
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

# 4b. Follow mode: no --run serves the run list and tracks new runs.
E="$T/empty"
mkdir -p "$E"
PORT2=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 "$KIT_ROOT/scripts/watch.py" --root "$E" --kit-root "$KIT_ROOT" \
  --host 127.0.0.1 --port "$PORT2" --no-open \
  >"$T/watch2.log" 2>&1 &
SERVER2_PID=$!
READY2=0
i=0
while [ "$i" -lt 50 ]; do
  if python3 - "$PORT2" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
port = sys.argv[1]
with urllib.request.urlopen("http://127.0.0.1:%s/api/runs" % port, timeout=2) as r:
    json.load(r)
PY
  then READY2=1; break
  fi
  sleep 0.1
  i=$((i + 1))
done
if [ "$READY2" != 1 ]; then
  printf 'FAIL follow-mode server did not start\n' >&2
  sed 's/^/  watch2.log: /' "$T/watch2.log" >&2 || true
  FAIL=1
elif ! python3 - "$PORT2" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request, urllib.error
port = sys.argv[1]
def get(path, expect=200):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%s%s" % (port, path), timeout=2) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        if e.code != expect:
            raise
        return e.code, e.read()
status, body = get("/api/runs")
assert status == 200 and json.loads(body) == {"runs": []}, (status, body)
status, body = get("/api/state", expect=404)
assert status == 404 and "no runs yet" in body.decode(), (status, body)
status, body = get("/")
assert status == 200 and b"latest" in body, status
PY
then printf 'FAIL follow mode must start empty and wait for runs\n' >&2; FAIL=1
else
  python3 "$KIT_ROOT/scripts/run-state.py" --root "$E" init --run follow-1 \
    --change demo-change --worktree-root "$E/.worktrees/demo" --repo demo \
    --base-ref main --base-sha abc123 --scope src >/dev/null 2>&1
  if ! python3 - "$PORT2" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
port = sys.argv[1]
def get(path):
    with urllib.request.urlopen("http://127.0.0.1:%s%s" % (port, path), timeout=2) as r:
        return r.status, r.read()
status, body = get("/api/runs")
runs = json.loads(body)["runs"]
assert len(runs) == 1 and runs[0]["runId"] == "follow-1", runs
status, body = get("/api/events?since=0")
data = json.loads(body)
assert data["runId"] == "follow-1" and data["nextOffset"] >= 1, data
PY
  then printf 'FAIL follow mode must pick up new runs\n' >&2; FAIL=1
  fi
  # ?run=bogus must 404 (exit 0 means the fetch raised 404 as expected).
  if python3 - "$PORT2" <<'PY' >/dev/null 2>&1
import sys, urllib.request, urllib.error
port = sys.argv[1]
try:
    urllib.request.urlopen("http://127.0.0.1:%s/api/events?run=bogus&since=0" % port, timeout=2)
except urllib.error.HTTPError as e:
    sys.exit(0 if e.code == 404 else 1)
sys.exit(1)
PY
  then :
  else printf 'FAIL unknown ?run= must 404\n' >&2; FAIL=1
  fi
fi
kill "$SERVER2_PID" 2>/dev/null || true
wait "$SERVER2_PID" 2>/dev/null || true

# 5. Dispatcher exposes watch.
if ! sh "$KIT_ROOT/scripts/astack" watch --help 2>&1 | grep -q 'Read-only'; then
  printf 'FAIL astack watch --help missing\n' >&2; FAIL=1
fi

[ "$FAIL" -eq 0 ]
