#!/usr/bin/env sh
# Version consistency: VERSION is the single source of truth for the kit
# version. Every AGENT_STACK_VERSION fallback must match it, so degraded
# installs (no VERSION file) and embedded defaults never report a stale
# version. Project config.conf copies are human-owned and never rewritten,
# so they are intentionally not checked here.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0

VERSION=$(awk 'NR == 1 { print $1; exit }' "$KIT_ROOT/VERSION")
[ -n "$VERSION" ] || { printf 'FAIL VERSION is empty\n' >&2; exit 1; }

check() {
  label=$1
  file=$2
  if [ ! -f "$file" ]; then
    printf 'FAIL %s: missing %s\n' "$label" "$file" >&2
    FAIL=1
    return 0
  fi
  got=$(awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' "$file")
  if [ "$got" != "$VERSION" ]; then
    printf 'FAIL %s: AGENT_STACK_VERSION=%s, expected %s (%s)\n' \
      "$label" "${got:-<missing>}" "$VERSION" "$file" >&2
    FAIL=1
  fi
}

check 'kit defaults' "$KIT_ROOT/.agent-stack/defaults.conf"
check 'embedded defaults' "$KIT_ROOT/scripts/setup-agent-stack.sh"
check 'standalone installer' "$KIT_ROOT/setup.sh"

[ "$FAIL" -eq 0 ]
