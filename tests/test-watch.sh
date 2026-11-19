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
  --claude-projects "$T/no-claude" --opencode-db "$T/no-opencode.db" \
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
assert meta["harness"]["name"], meta["harness"]
status, body = get("/")
assert status == 200 and b"watch-1" in body, status
assert b"Agent Studio" in body, "viewer identity"
assert b"__ASTACK_CHARACTERS__" not in body, "atlas placeholder must be resolved"
assert b"__ASTACK_OFFICE__" not in body, "office engine must be embedded"
assert b"AgentOffice" in body and b"office-canvas" in body, "interactive office is present"
assert b"data:image/webp;base64," in body, "Kenney sprites are embedded, not remote"
status, body = get("/api/transcript?since=0")
tx = json.loads(body)
assert status == 200 and tx["enabled"] is True and tx["entries"] == [] and tx["runId"] == "watch-1", tx
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
  --host 127.0.0.1 --port "$PORT2" --no-open --no-transcripts \
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
status, body = get("/api/transcript")
tx = json.loads(body)
assert tx["enabled"] is False and tx["entries"] == [], "--no-transcripts must not read sessions"
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

# 6. Asset loader fallback and model parsing match installer semantics.
if ! python3 - "$KIT_ROOT" "$T" <<'PY'
import importlib.util, json, pathlib, sys
kit, temp = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("watch", kit / "scripts/watch.py")
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)
config = temp / "duplicates.conf"
config.write_text("OPENCODE_RESOLVER_VARIANT=max\nOPENCODE_RESOLVER_VARIANT=high\n")
assert watch.read_config(config)["OPENCODE_RESOLVER_VARIANT"] == "max"
atlas = json.loads((kit / ".agent-stack/templates/watch/characters.json").read_text())
assert atlas["version"] >= 3 and atlas["scale"] >= 2, "HiDPI atlas"
assert len(atlas["sources"]) == 7
assert atlas["frames"] == 8
assert set(atlas["clips"]) == {"idle", "drive", "sit", "walk"}
assert len(atlas["directions"]) == 8
assert len(atlas["sequences"]) == 18
assert {s["direction"] for s in atlas["sequences"] if s["clip"] == "walk"} == set(atlas["directions"])
assert all(len(s["anchor"]) == 2 and all(0 <= n <= 1 for n in s["anchor"]) for s in atlas["sources"])
assert all(set(atlas["clips"]) <= set(s["animations"]) for s in atlas["sources"])
for s in atlas["sources"]:
    assert s["image"].startswith("data:image/webp;base64,")
    assert len(s["tiles"]) == len(atlas["sequences"])
    for x, y, w, h, ax, ay in s["tiles"]:
        # every frame strip fits the sheet, and the ground anchor is inside the crop
        assert x + w * atlas["frames"] <= s["sheet"][0] and y + h <= s["sheet"][1]
        assert 0 <= ax <= w and 0 <= ay <= h
fallback = temp / "artless-kit/.agent-stack/templates/watch"
fallback.mkdir(parents=True)
(fallback / "watch.html").write_text('<script id="character-atlas">__ASTACK_CHARACTERS__</script>')
assert '>null<' in watch.load_template(str(temp / "artless-kit"))
PY
then printf 'FAIL watch embedded art/fallback/config parsing\n' >&2; FAIL=1
fi

# 7. Harness transcripts: only this project's sessions that mention the run,
#    inside its time window, read-only, with secrets redacted and output clipped.
if ! python3 - "$KIT_ROOT" "$T" <<'PY'
import importlib.util, json, pathlib, re, sqlite3, sys, time
from datetime import datetime, timezone
kit, temp = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("watch", kit / "scripts/watch.py")
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)
root = (temp / "tx-project").resolve()
run = "tx-1"
(root / ".agent-stack/runs" / run).mkdir(parents=True)
now = time.time()
iso = lambda t: datetime.fromtimestamp(t, tz=timezone.utc).isoformat()
(root / ".agent-stack/runs" / run / "state.json").write_text(json.dumps({"runId": run, "phase": "implement"}))
(root / ".agent-stack/runs" / run / "events.jsonl").write_text(
    json.dumps({"type": "init", "ts": iso(now - 120), "detail": "run created"}) + "\n")

projects = temp / "claude-projects"
slug = re.sub(r"[^A-Za-z0-9]", "-", str(root))
main_dir = projects / slug
sub_dir = main_dir / "sess-main" / "subagents"
sub_dir.mkdir(parents=True)
def line(kind, content, at, uid, cwd=str(root), **extra):
    role = "assistant" if kind == "assistant" else "user"
    return json.dumps(dict({"type": kind, "uuid": uid, "timestamp": iso(at), "cwd": cwd,
                            "message": {"role": role, "content": content}}, **extra)) + "\n"
long_output = "\n".join("line %d" % i for i in range(300))
fake_key = "sk" + "-" + "abcdefghij" * 3  # assembled so no key-shaped literal is committed
main = main_dir / "sess-main.jsonl"
main.write_text(
    line("user", "build it for run " + run, now - 100, "u1") +
    line("user", "<system-reminder>internal</system-reminder>", now - 99, "u0", isMeta=True) +
    line("assistant", [{"type": "thinking", "thinking": ""}, {"type": "text", "text": "Starting."},
                       {"type": "tool_use", "id": "t1", "name": "Bash",
                        "input": {"command": "OPENAI_API_KEY=" + fake_key + " npm test"}}], now - 90, "a1") +
    line("user", [{"type": "tool_result", "tool_use_id": "t1", "content": "12 passed\npassword=hunter2hunter2"}], now - 89, "r1") +
    line("assistant", [{"type": "tool_use", "id": "t2", "name": "Read", "input": {"file_path": str(root / "src/app.js")}}], now - 80, "a2") +
    line("user", [{"type": "tool_result", "tool_use_id": "t2", "content": long_output}], now - 79, "r2") +
    line("assistant", [{"type": "text", "text": "outside the project"}], now - 70, "a3", cwd="/somewhere/else"))
(main_dir / "sess-other.jsonl").write_text(line("assistant", [{"type": "text", "text": "unrelated session"}], now - 60, "x1"))
(sub_dir / "agent-abc123.meta.json").write_text(json.dumps({"agentType": "developer", "finished": True,
                                                           "description": "Implement it"}))
(sub_dir / "agent-abc123.jsonl").write_text(
    line("user", "You are the developer for this run.", now - 75, "s1", isSidechain=True) +
    line("assistant", [{"type": "tool_use", "id": "t3", "name": "Edit",
                        "input": {"file_path": str(root / "a.js"), "old_string": "a", "new_string": "b"}}], now - 74, "s2") +
    line("user", [{"type": "tool_result", "tool_use_id": "t3", "content": "boom", "is_error": True}], now - 73, "s3"))
# A sibling project whose directory merely shares the prefix is never read.
sibling = projects / (slug + "-2")
sibling.mkdir()
(sibling / "s.jsonl").write_text(line("assistant", [{"type": "text", "text": "sibling " + run}], now - 50, "y1",
                                      cwd=str(root) + "-2"))

db = temp / "opencode.db"
con = sqlite3.connect(db)
con.execute("create table session_v2 (id text, parent_id text, directory text, title text, agent text, "
            "model text, time_created integer, time_updated integer)")
con.execute("create table session_message (id text, session_id text, type text, seq integer, "
            "time_created integer, time_updated integer, data text)")
ms = lambda t: int(t * 1000)
con.executemany("insert into session_v2 values (?,?,?,?,?,?,?,?)", [
    ("ses_root0001", None, str(root), "deliver", "build", json.dumps({"id": "m", "providerID": "p"}), ms(now - 100), ms(now - 10)),
    ("ses_child002", "ses_root0001", str(root / ".worktrees/x"), "review", "design-qa",
     json.dumps({"id": "m", "providerID": "p", "variant": "max"}), ms(now - 60), ms(now - 20)),
    ("ses_elsewhere", None, "/other/project", "other", "build", "{}", ms(now - 60), ms(now - 20)),
])
con.executemany("insert into session_message values (?,?,?,?,?,?,?)", [
    ("m1", "ses_root0001", "user", 1, ms(now - 100), ms(now - 100), json.dumps({"text": "start run " + run})),
    ("m2", "ses_child002", "assistant", 1, ms(now - 50), ms(now - 40), json.dumps({
        "time": {"created": ms(now - 50), "completed": ms(now - 40)}, "content": [
            {"type": "reasoning", "text": "Checking contrast first."},
            {"type": "tool", "id": "call_1", "name": "bash", "state": {"status": "completed",
             "input": {"command": "npx axe"}, "content": [{"type": "text", "text": "0 violations"}]}},
            {"type": "text", "text": "Looks good."}]})),
    ("m3", "ses_elsewhere", "user", 1, ms(now - 60), ms(now - 60), json.dumps({"text": "mentions " + run})),
])
con.commit()
con.close()

index = watch.TranscriptIndex(str(root), run, claude_dir=str(projects), opencode_db=str(db))
index.refresh()
snap = index.snapshot(0)
entries = snap["entries"]
blob = json.dumps(entries)
by = lambda **kw: [e for e in entries if all(e.get(k) == v for k, v in kw.items())]
assert {s["agent"] for s in snap["sources"]} == {"resolver", "developer", "design-qa"}, snap["sources"]
assert "unrelated session" not in blob and "outside the project" not in blob and "sibling" not in blob
assert fake_key not in blob and "hunter2hunter2" not in blob, "secrets are redacted"
bash = by(kind="tool", tool="Bash")[0]
assert "[redacted key]" in bash["title"] and bash["agent"] == "resolver"
assert "12 passed" in by(kind="result", callId="t1")[0]["output"]
read = by(kind="result", callId="t2")[0]
assert read["truncated"] and read["lines"] == 300 and read["output"].count("\n") < 200
assert by(kind="tool", tool="Read")[0]["title"] == "src/app.js", "paths are shown relative to the project"
assert by(kind="thinking", agent="resolver")[0]["hidden"] is True
assert not [e for e in entries if "internal" in e.get("text", "")], "meta reminders are not prompts"
edit = by(kind="tool", tool="Edit")[0]
assert edit["agent"] == "developer" and "- a" in edit["diff"] and "+ b" in edit["diff"]
assert by(kind="result", callId="t3")[0]["error"] is True
assert by(kind="prompt", agent="developer")[0]["role"] == "delegation"
qa = [e for e in entries if e["agent"] == "design-qa"]
assert [e["kind"] for e in qa] == ["thinking", "tool", "result", "text"], qa
assert qa[0]["text"] == "Checking contrast first." and qa[1]["title"] == "npx axe" and qa[2]["output"] == "0 violations"
assert by(kind="prompt", harness="opencode")[0]["agent"] == "resolver"
assert len({e["seq"] for e in entries}) == len(entries)
# Incremental: appended lines arrive once, after the last seq.
with open(main, "a") as fh:
    fh.write(line("assistant", [{"type": "text", "text": "Next step."}], now - 5, "a9"))
index.last_read = 0
index.refresh()
fresh = index.snapshot(snap["nextSeq"])["entries"]
assert [e["text"] for e in fresh] == ["Next step."], fresh
assert watch.build_parser().parse_args(["--no-transcripts"]).transcripts is False
PY
then printf 'FAIL watch harness transcripts\n' >&2; FAIL=1
fi

[ "$FAIL" -eq 0 ]
