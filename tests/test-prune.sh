#!/usr/bin/env sh
# Prune removes generated files only for platforms that are disabled.
# Repro: init --platforms claude, then init --platforms cursor, then prune
# must leave the cursor skill mirrors in place so check does not report them
# missing.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-prune.XXXXXX")
SKIP=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-prune-skip.XXXXXX")
trap 'rm -rf "$ROOT" "$SKIP"' EXIT INT TERM

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=1
}

run() {
  sh "$KIT_ROOT/scripts/setup-agent-stack.sh" "$@" --root "$ROOT" --kit-root "$KIT_ROOT"
}

run init --platforms claude --mcp none >/dev/null 2>&1
run init --platforms cursor --mcp none >/dev/null 2>&1

config=$ROOT/.agent-stack/config.conf
grep -q '^ENABLE_CLAUDE=0$' "$config" || fail 're-init --platforms cursor must persist ENABLE_CLAUDE=0'
grep -q '^ENABLE_CURSOR=1$' "$config" || fail 're-init --platforms cursor must persist ENABLE_CURSOR=1'
[ -f "$ROOT/.cursor/skills/project-context/SKILL.md" ] || fail 'cursor skill missing before prune'
[ -f "$ROOT/.claude/skills/project-context/SKILL.md" ] || fail 'claude skill missing before prune'

run prune >"$ROOT/prune.log" 2>&1 || fail 'prune exited nonzero'

if [ ! -f "$ROOT/.cursor/skills/project-context/SKILL.md" ]; then
  fail 'prune deleted a skill for the enabled cursor platform'
fi
if [ ! -f "$ROOT/.cursor/agents/resolver.md" ]; then
  fail 'prune deleted a cursor agent for the enabled platform'
fi
if [ -e "$ROOT/.claude/skills/project-context/SKILL.md" ]; then
  fail 'prune left a claude skill after claude was disabled'
fi
if grep -q 'claude/skills' "$ROOT/.agent-stack/generated.manifest"; then
  fail 'manifest still records claude skills after prune'
fi
if ! grep -q 'cursor/skills' "$ROOT/.agent-stack/generated.manifest"; then
  fail 'manifest dropped cursor skills for an enabled platform'
fi

if ! run check >"$ROOT/check.log" 2>&1; then
  fail 'check failed after prune'
  sed 's/^/  /' "$ROOT/check.log" >&2
fi
if grep -q 'missing ' "$ROOT/check.log"; then
  fail 'check reported missing files after prune'
  sed 's/^/  /' "$ROOT/check.log" >&2
fi

# One-shot platform flags must not delete a platform config still enables.
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$SKIP" --kit-root "$KIT_ROOT" \
  --platforms claude --mcp none >/dev/null 2>&1
if sh "$KIT_ROOT/scripts/setup-agent-stack.sh" prune --root "$SKIP" --kit-root "$KIT_ROOT" \
  --skip-claude >"$SKIP/prune.log" 2>&1; then
  fail 'prune --skip-claude must exit nonzero'
fi
if [ ! -f "$SKIP/.claude/skills/project-context/SKILL.md" ]; then
  fail 'prune --skip-claude deleted a skill for an enabled platform'
fi

[ "$FAIL" -eq 0 ]
