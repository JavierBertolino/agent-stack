#!/usr/bin/env sh
# The non-git fallback scans project files but must not inspect dependencies.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-public-safety.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/node_modules/example-package"
printf 'fixture\n' > "$T/README.md"
printf '/%s/third-party-build/path\n' home > "$T/node_modules/example-package/README.md"

output=$(sh "$KIT_ROOT/scripts/check-public-safety.sh" --kit-root "$T" 2>&1) \
  || { printf 'FAIL public-safety scanned node_modules:\n%s\n' "$output" >&2; exit 1; }
printf '%s\n' "$output" | grep -q 'no private references found' \
  || { printf 'FAIL public-safety fallback did not finish cleanly:\n%s\n' "$output" >&2; exit 1; }
