#!/usr/bin/env sh
# Expected cross-host skill visibility is summarized without hiding skills.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-skill-overlap.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM

sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$T" \
  --kit-root "$KIT_ROOT" --platforms opencode,claude,codex --mcp none \
  >/dev/null 2>&1
output=$(sh "$KIT_ROOT/scripts/doctor.sh" --root "$T" --kit-root "$KIT_ROOT" 2>&1)
summary_count=$(printf '%s\n' "$output" \
  | grep -c 'expected OpenCode skill visibility overlap across' || true)
[ "$summary_count" -eq 1 ] \
  || { printf 'FAIL expected one overlap summary, got %s:\n%s\n' "$summary_count" "$output" >&2; exit 1; }
printf '%s\n' "$output" | grep -q 'project-context via .*\.opencode/skills/project-context/SKILL.md' \
  || { printf 'FAIL overlap summary omitted a skill/path:\n%s\n' "$output" >&2; exit 1; }
if printf '%s\n' "$output" | grep -q 'skill .* visible to opencode through'; then
  printf 'FAIL doctor still emits per-skill overlap noise:\n%s\n' "$output" >&2
  exit 1
fi
