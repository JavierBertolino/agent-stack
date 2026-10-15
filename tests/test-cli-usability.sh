#!/usr/bin/env sh
# Init output, non-TTY defaults, git warning, uninstall, and wizard QA default.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-cli.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=1
}

setup() {
  sh "$KIT_ROOT/scripts/setup-agent-stack.sh" "$@" --kit-root "$KIT_ROOT"
}

# Non-TTY init without --platforms keeps working and names the defaults.
N=$WORK/nontty
mkdir -p "$N"
setup init --root "$N" --mcp none >"$N/init.log" 2>&1 || fail 'non-tty init without --platforms failed'
grep -q 'Non-interactive init is using opencode, claude, codex, cursor' "$N/init.log" \
  || fail 'non-tty init must print the platform defaults'
grep -q 'not a git repository' "$N/init.log" || fail 'init must warn when the target is not a git repo'

# Explicit --platforms does not also claim the config defaults were used.
E=$WORK/explicit
mkdir -p "$E"
setup init --root "$E" --platforms opencode --mcp none >"$E/init.log" 2>&1 || fail 'explicit init failed'
if grep -q 'Non-interactive' "$E/init.log"; then
  fail 'explicit --platforms must not print the non-interactive default notice'
fi

# Default output is a summary. --verbose keeps the per-file list.
grep -q 'Created ' "$E/init.log" || fail 'init must print a created summary'
if grep -q '^created ' "$E/init.log"; then
  fail 'default init must not print one created line per file'
fi
if ! grep -q 'npm i -g @fission-ai/openspec' "$E/init.log"; then
  if ! command -v openspec >/dev/null 2>&1; then
    fail 'init must hint at npm i -g @fission-ai/openspec when openspec is absent'
  fi
fi
V=$WORK/verbose
mkdir -p "$V"
setup init --root "$V" --platforms opencode --mcp none --verbose >"$V/verbose.log" 2>&1 || fail 'verbose init failed'
grep -q '^created ' "$V/verbose.log" || fail '--verbose must list created files'

# Usage talks about astack, including uninstall.
setup --help >"$WORK/help.log" 2>&1 || fail 'help failed'
grep -q 'astack init' "$WORK/help.log" || fail 'help must show astack init'
if grep -q 'setup-agent-stack.sh init' "$WORK/help.log"; then
  fail 'help must not lead with setup-agent-stack.sh init'
fi
grep -q 'astack uninstall' "$WORK/help.log" || fail 'help must document astack uninstall'
sh "$KIT_ROOT/scripts/astack" --help >"$WORK/astack-help.log" 2>&1 || fail 'astack help failed'
grep -q 'astack uninstall' "$WORK/astack-help.log" || fail 'astack --help must list uninstall'

# Uninstall refuses without --yes when stdin is not a terminal, and --yes
# removes generated files while leaving the project guides.
U=$WORK/uninstall
mkdir -p "$U"
setup init --root "$U" --platforms opencode --mcp linear >"$U/init.log" 2>&1 || fail 'uninstall fixture init failed'
[ -f "$U/.opencode/agents/resolver.md" ] || fail 'fixture missing a generated agent'
if setup uninstall --root "$U" >"$U/refuse.log" 2>&1; then
  fail 'uninstall without --yes must exit nonzero when not interactive'
fi
[ -f "$U/.opencode/agents/resolver.md" ] || fail 'refused uninstall removed a generated file'
setup uninstall --root "$U" --yes >"$U/uninstall.log" 2>&1 || fail 'uninstall --yes failed'
if [ -f "$U/.opencode/agents/resolver.md" ]; then
  fail 'uninstall --yes left a generated agent'
fi
if [ -f "$U/.opencode/skills/project-context/SKILL.md" ]; then
  fail 'uninstall --yes left a generated skill'
fi
[ -f "$U/UX_AGENTS.md" ] || fail 'uninstall removed the project UX guide'
if [ -f "$U/opencode.jsonc" ] && grep -q 'mcp.linear.app' "$U/opencode.jsonc"; then
  fail 'uninstall left the managed linear MCP entry'
fi
if [ -f "$U/scripts/qa/ask-jev.ts" ]; then
  fail 'uninstall left an unchanged QA helper'
fi

# --force continues a non-git init. It does not confirm uninstall.
FU=$WORK/force-uninstall
mkdir -p "$FU"
setup init --root "$FU" --platforms opencode --mcp none >/dev/null 2>&1 || fail 'force-uninstall fixture init failed'
if setup uninstall --root "$FU" --force >"$FU/force.log" 2>&1; then
  fail 'uninstall --force must exit nonzero when not interactive'
fi
[ -f "$FU/.opencode/agents/resolver.md" ] || fail 'uninstall --force removed a generated file'

# A terminal stdin with redirected stderr must not block on the git prompt.
# astack upgrade discards sync output and would otherwise wait forever.
python3 - "$KIT_ROOT" "$WORK/git-stderr" <<'PY' || fail 'non-git init blocked when stderr was not a terminal'
import os, pty, select, subprocess, sys, time
kit, root = sys.argv[1], sys.argv[2]
os.makedirs(root, exist_ok=True)
master, slave = pty.openpty()
err = open(os.path.join(root, "err.log"), "w")
proc = subprocess.Popen(
    ["sh", os.path.join(kit, "scripts/setup-agent-stack.sh"), "init",
     "--root", root, "--kit-root", kit, "--platforms", "opencode", "--mcp", "none"],
    stdin=slave, stdout=slave, stderr=err,
)
os.close(slave)
deadline = time.time() + 30
while proc.poll() is None:
    if time.time() > deadline:
        proc.kill()
        sys.stderr.write("init blocked on the git prompt\n")
        sys.exit(1)
    ready, _, _ = select.select([master], [], [], 0.2)
    if ready:
        try:
            os.read(master, 4096)
        except OSError:
            break
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    sys.stderr.write("init blocked on the git prompt\n")
    sys.exit(1)
err.close()
if proc.returncode != 0:
    sys.stderr.write("init exited %s\n" % proc.returncode)
    sys.exit(1)
os.close(master)
PY

# README names five wizard steps, matching the installer.
readme=$KIT_ROOT/README.md
grep -q 'five prompts' "$readme" || fail 'README must say the wizard has five prompts'
for step in 'Coding agents' 'Integrations' 'Specs' 'QA' 'Models'; do
  grep -q "$step" "$readme" || fail "README wizard list missing $step"
done

# Interactive QA defaults to Configure later. Enter through the wizard must
# finish without asking for an API key.
W=$WORK/wizard
mkdir -p "$W"
python3 - "$KIT_ROOT" "$W" <<'PY' || fail 'wizard QA default is not Configure later'
import os, select, subprocess, sys, time
kit, root = sys.argv[1], sys.argv[2]
try:
    import pty
except ImportError:
    sys.stderr.write("pty unavailable\n")
    sys.exit(1)
master, slave = pty.openpty()
env = os.environ.copy()
env["AGENT_STACK_PLAIN"] = "1"
env["TERM"] = "xterm"
proc = subprocess.Popen(
    ["sh", os.path.join(kit, "scripts/setup-agent-stack.sh"), "init",
     "--root", root, "--kit-root", kit, "--skip-models", "--force"],
    stdin=slave, stdout=slave, stderr=slave, env=env,
)
os.close(slave)
buf = b""
deadline = time.time() + 25
marked = False

def send(data):
    try:
        os.write(master, data)
    except OSError:
        return False
    return True

while time.time() < deadline and proc.poll() is None:
    ready, _, _ = select.select([master], [], [], 0.4)
    if ready:
        try:
            chunk = os.read(master, 8192)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
    text = buf.decode("utf-8", "replace")
    if "Set up Jev" in text and "Configure later" in text:
        screen = text.split("Set up Jev")[-1]
        if "[x] Configure later" in screen and "[x] Configure Jev now" not in screen:
            marked = True
            send(b"\r")
            break
        continue
    if "Space selects" in text or "Enter confirms" in text or "Select [" in text:
        if send(b"\r"):
            buf = b""
            time.sleep(0.15)
try:
    proc.wait(timeout=20)
except subprocess.TimeoutExpired:
    proc.kill()
    sys.stderr.write("wizard timed out\n")
    sys.exit(1)
if not marked:
    sys.stderr.write(buf.decode("utf-8", "replace")[-2000:])
    sys.exit(1)
if proc.returncode != 0:
    sys.stderr.write("wizard init exited %s\n" % proc.returncode)
    sys.exit(1)
PY

# Empty API key during the wizard skips instead of aborting.
K=$WORK/emptykey
mkdir -p "$K"
python3 - "$KIT_ROOT" "$K" <<'PY' || fail 'empty Jev API key aborted the wizard'
import os, select, subprocess, sys, time
kit, root = sys.argv[1], sys.argv[2]
import pty
master, slave = pty.openpty()
env = os.environ.copy()
env["AGENT_STACK_PLAIN"] = "1"
env["TERM"] = "xterm"
proc = subprocess.Popen(
    ["sh", os.path.join(kit, "scripts/setup-agent-stack.sh"), "init",
     "--root", root, "--kit-root", kit, "--skip-models", "--force"],
    stdin=slave, stdout=slave, stderr=slave, env=env,
)
os.close(slave)
buf = b""
phase = "seek-jev"
deadline = time.time() + 25

def send(data):
    try:
        os.write(master, data)
    except OSError:
        return False
    return True

while time.time() < deadline and proc.poll() is None:
    ready, _, _ = select.select([master], [], [], 0.3)
    if ready:
        try:
            chunk = os.read(master, 8192)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
    text = buf.decode("utf-8", "replace")
    if phase == "seek-jev" and "Set up Jev" in text and "Configure later" in text:
        send(b"\x1b[A ")
        phase = "select-now"
        buf = b""
        time.sleep(0.25)
        continue
    if phase == "seek-jev" and ("Space selects" in text or "Enter confirms" in text or "Select [" in text):
        send(b"\r")
        buf = b""
        time.sleep(0.15)
        continue
    if phase == "select-now" and "[x] Configure Jev now" in text:
        send(b"\r")
        phase = "provider"
        buf = b""
        time.sleep(0.25)
        continue
    if phase == "provider" and "TypeSafe direct" in text:
        send(b"\r")
        phase = "key"
        buf = b""
        time.sleep(0.25)
        continue
    if phase == "key" and "API key" in text:
        send(b"\r")
        phase = "done"
        time.sleep(0.4)
        break
try:
    proc.wait(timeout=20)
except subprocess.TimeoutExpired:
    proc.kill()
    sys.stderr.write("empty-key wizard timed out in phase %s\n" % phase)
    sys.stderr.write(buf.decode("utf-8", "replace")[-1500:])
    sys.exit(1)
out = buf.decode("utf-8", "replace")
if proc.returncode != 0 or "no value entered" in out:
    sys.stderr.write("phase=%s exit=%s\n" % (phase, proc.returncode))
    sys.stderr.write(out[-2000:])
    sys.exit(1)
PY

# README command list includes uninstall.
grep -q 'astack uninstall' "$KIT_ROOT/README.md" || fail 'README must document astack uninstall'

[ "$FAIL" -eq 0 ]
