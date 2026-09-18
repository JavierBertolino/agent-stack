#!/usr/bin/env sh
# Installer round-trip tests: init, idempotent sync, check, drift detection,
# governance status, sources manifest, and run-state helper behavior.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-installer.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM

sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$T" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none >"$T/init.log" 2>&1 \
  || { printf 'FAIL init exited nonzero\n' >&2; FAIL=1; }
grep -q 'governance UX_AGENTS: scaffold-only' "$T/init.log" \
  || { printf 'FAIL init must report scaffold-only governance\n' >&2; FAIL=1; }
[ -f "$T/.agent-stack/sources.manifest" ] \
  || { printf 'FAIL sources.manifest missing after init\n' >&2; FAIL=1; }
[ -f "$T/.opencode/skills/ux-design/SKILL.md" ] \
  || { printf 'FAIL opencode skill mirror missing\n' >&2; FAIL=1; }
[ -f "$T/.agents/skills/git-delivery/SKILL.md" ] \
  || { printf 'FAIL codex skill mirror missing\n' >&2; FAIL=1; }
[ -f "$T/.agent-stack/contracts/handoff.schema.json" ] \
  || { printf 'FAIL contract not installed\n' >&2; FAIL=1; }

sh "$KIT_ROOT/scripts/setup-agent-stack.sh" sync --root "$T" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none >"$T/sync.log" 2>&1 \
  || { printf 'FAIL sync exited nonzero\n' >&2; FAIL=1; }
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" check --root "$T" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none >"$T/check.log" 2>&1 \
  || { printf 'FAIL check on clean install must pass\n' >&2; FAIL=1; }

# Drift detection: check must fail read-only on a missing mirror.
rm "$T/.claude/skills/ui-review/SKILL.md"
if sh "$KIT_ROOT/scripts/setup-agent-stack.sh" check --root "$T" --kit-root "$KIT_ROOT" --platforms claude --mcp none >"$T/drift.log" 2>&1; then
  printf 'FAIL check must fail on missing mirror\n' >&2; FAIL=1
fi
[ -f "$T/.claude/skills/ui-review/SKILL.md" ] && { printf 'FAIL check must not reinstall\n' >&2; FAIL=1; }
grep -q 'missing .*ui-review' "$T/drift.log" || { printf 'FAIL check must name the missing file\n' >&2; FAIL=1; }

# Run-state helper: invalid transitions rejected, stale detected.
R=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-runstate.XXXXXX")
python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" init --run t-1 --issue LIN-9 --change t-change --worktree-root "$R/wt" --repo r --base-ref main --base-sha 000 --scope s >/dev/null \
  || { printf 'FAIL run init\n' >&2; FAIL=1; }
if python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" transition --run t-1 --to implement >/dev/null 2>&1; then
  printf 'FAIL invalid transition accepted\n' >&2; FAIL=1
fi
python3 "$KIT_ROOT/scripts/run-state.py" --root "$R" validate --run t-1 --kit-root "$KIT_ROOT" >/dev/null \
  || { printf 'FAIL fresh run must validate\n' >&2; FAIL=1; }
rm -rf "$R"

[ "$FAIL" -eq 0 ]
