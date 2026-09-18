#!/usr/bin/env sh
# Upgrade tests: unchanged managed sources update, human edits survive with
# a visible conflict, and --check is a dry run.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-upgrade.XXXXXX")
NK=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-newkit.XXXXXX")
trap 'rm -rf "$T" "$NK"' EXIT INT TERM

sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$T" --kit-root "$KIT_ROOT" --platforms opencode --mcp none >/dev/null 2>&1
# User customization that must survive.
printf '\n# project customization\n' >> "$T/.agent-stack/roles/resolver.md"
# Fake newer kit: changed managed file + brand-new skill.
mkdir -p "$NK/.agent-stack"
cp -r "$KIT_ROOT/.agent-stack/roles" "$KIT_ROOT/.agent-stack/skills" "$KIT_ROOT/.agent-stack/contracts" "$NK/.agent-stack/"
printf '\n# upstream fix\n' >> "$NK/.agent-stack/skills/ux-design/SKILL.md"
printf '\n# upstream fix\n' >> "$NK/.agent-stack/roles/resolver.md"

# --check is a dry run: reports pending work, changes nothing.
if sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$NK" --check >/dev/null 2>&1; then
  printf 'FAIL upgrade --check must exit 1 with pending work\n' >&2; FAIL=1
fi
grep -q 'upstream fix' "$T/.agent-stack/skills/ux-design/SKILL.md" && { printf 'FAIL --check must not modify files\n' >&2; FAIL=1; }

if sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$NK" >/dev/null 2>&1; then
  printf 'FAIL upgrade with conflicts must exit 1\n' >&2; FAIL=1
fi
grep -q 'project customization' "$T/.agent-stack/roles/resolver.md" \
  || { printf 'FAIL user edit lost on upgrade\n' >&2; FAIL=1; }
[ -f "$T/.agent-stack/roles/resolver.md.kit-new" ] \
  || { printf 'FAIL conflict must write .kit-new\n' >&2; FAIL=1; }
grep -q 'upstream fix' "$T/.agent-stack/skills/ux-design/SKILL.md" \
  || { printf 'FAIL unchanged managed source must update\n' >&2; FAIL=1; }
grep -q 'upstream fix' "$T/.agent-stack/roles/resolver.md" \
  && { printf 'FAIL customized file must not be overwritten\n' >&2; FAIL=1; }

[ "$FAIL" -eq 0 ]
