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

# A stale project version is pending work even if every managed source already
# matches the installed kit. This is the state after updating only the CLI.
CURRENT_VERSION=$(cat "$T/.agent-stack/.kit-version")
STALE_VERSION=project-version-unknown
printf '%s\n' "$STALE_VERSION" > "$T/.agent-stack/.kit-version"
set +e
version_check=$(sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$KIT_ROOT" --check 2>&1)
version_status=$?
set -e
[ "$version_status" -eq 1 ] \
  || { printf 'FAIL upgrade --check must exit 1 for stale project version\n' >&2; FAIL=1; }
printf '%s\n' "$version_check" | grep -q "would align project kit version ($STALE_VERSION → $CURRENT_VERSION)" \
  || { printf 'FAIL upgrade --check must report project version transition\n' >&2; FAIL=1; }
printf '%s\n' "$version_check" | grep -q 'upgrade check: 1 pending update(s), 0 conflict(s)' \
  || { printf 'FAIL stale project version must count as one pending update\n' >&2; FAIL=1; }
[ "$(cat "$T/.agent-stack/.kit-version")" = "$STALE_VERSION" ] \
  || { printf 'FAIL version check must not modify .kit-version\n' >&2; FAIL=1; }

version_apply=$(sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$KIT_ROOT" 2>&1)
printf '%s\n' "$version_apply" | grep -q 'upgrade: 1 updated, 0 conflict(s)' \
  || { printf 'FAIL apply must count the version marker update\n' >&2; FAIL=1; }
[ "$(cat "$T/.agent-stack/.kit-version")" = "$CURRENT_VERSION" ] \
  || { printf 'FAIL apply must record the installed kit version\n' >&2; FAIL=1; }

rm "$T/.agent-stack/.kit-version"
set +e
missing_check=$(sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$KIT_ROOT" --check 2>&1)
missing_status=$?
set -e
[ "$missing_status" -eq 1 ] \
  || { printf 'FAIL missing project version must be pending work\n' >&2; FAIL=1; }
printf '%s\n' "$missing_check" | grep -q "would align project kit version (unknown → $CURRENT_VERSION)" \
  || { printf 'FAIL missing version must report unknown as the old version\n' >&2; FAIL=1; }
doctor_output=$(sh "$KIT_ROOT/scripts/doctor.sh" --root "$T" --kit-root "$KIT_ROOT" 2>&1)
printf '%s\n' "$doctor_output" | grep -q "project kit version is missing" \
  || { printf 'FAIL doctor must warn when the project version marker is missing\n' >&2; FAIL=1; }
: > "$T/.agent-stack/.kit-version"
empty_check=$(sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$KIT_ROOT" --check 2>&1 || true)
printf '%s\n' "$empty_check" | grep -q "would align project kit version (unknown → $CURRENT_VERSION)" \
  || { printf 'FAIL empty version marker must be reported as unknown\n' >&2; FAIL=1; }
sh "$KIT_ROOT/scripts/upgrade-agent-stack.sh" --root "$T" --kit-root "$KIT_ROOT" >/dev/null 2>&1
printf '%s\n' "$CURRENT_VERSION" > "$T/.agent-stack/.kit-version"

# User customization that must survive.
printf '\n# project customization\n' >> "$T/.agent-stack/roles/resolver.md"
# Fake newer kit: changed managed files (role, ux-design, and the new
# astack-ops skill).
mkdir -p "$NK/.agent-stack"
cp -r "$KIT_ROOT/.agent-stack/roles" "$KIT_ROOT/.agent-stack/skills" "$KIT_ROOT/.agent-stack/contracts" "$KIT_ROOT/.agent-stack/resources" "$NK/.agent-stack/"
printf '\n# upstream fix\n' >> "$NK/.agent-stack/skills/ux-design/SKILL.md"
printf '\n# upstream fix\n' >> "$NK/.agent-stack/skills/astack-ops/SKILL.md"
printf '\n# upstream fix\n' >> "$NK/.agent-stack/roles/resolver.md"
printf '\n// upstream resource update\n' >> "$NK/.agent-stack/resources/web-qa/questions.ts"
rm "$T/scripts/jev/action-selection.ts"
printf '\n// project customization\n' >> "$T/scripts/jev/validate-action-selection.ts"
printf '\n// mobile project customization\n' >> "$T/scripts/mobile-qa/questions-mobile.ts"

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
grep -q 'upstream fix' "$T/.agent-stack/skills/astack-ops/SKILL.md" \
  || { printf 'FAIL new astack-ops skill must update on upgrade\n' >&2; FAIL=1; }
grep -q 'upstream fix' "$T/.agent-stack/roles/resolver.md" \
  && { printf 'FAIL customized file must not be overwritten\n' >&2; FAIL=1; }
grep -q 'upstream resource update' "$T/scripts/qa/questions.ts" \
  || { printf 'FAIL unchanged question resource must update\n' >&2; FAIL=1; }
[ -f "$T/scripts/mobile-qa/questions-mobile.ts.kit-new" ] \
  || { printf 'FAIL customized question resource must receive .kit-new\n' >&2; FAIL=1; }
grep -q 'mobile project customization' "$T/scripts/mobile-qa/questions-mobile.ts" \
  || { printf 'FAIL mobile question resource customization lost\n' >&2; FAIL=1; }
[ -f "$T/scripts/jev/action-selection.ts" ] \
  || { printf 'FAIL missing shared Jev resource must be restored on upgrade\n' >&2; FAIL=1; }
grep -q 'project customization' "$T/scripts/jev/validate-action-selection.ts" \
  || { printf 'FAIL project-owned Jev resource must survive upgrade\n' >&2; FAIL=1; }

[ "$FAIL" -eq 0 ]
