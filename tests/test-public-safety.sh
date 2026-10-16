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

# `npx agent-stack init` is the published package command. The bare alias stays rejected.
N=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-public-safety-npx.XXXXXX")
B=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-public-safety-bare.XXXXXX")
trap 'rm -rf "$T" "$N" "$B"' EXIT INT TERM
printf 'npx agent-stack init\n' > "$N/README.md"
sh "$KIT_ROOT/scripts/check-public-safety.sh" --kit-root "$N" >/dev/null \
  || { printf 'FAIL npx agent-stack init must be allowed\n' >&2; exit 1; }
printf 'agent-stack init\n' > "$B/README.md"
if sh "$KIT_ROOT/scripts/check-public-safety.sh" --kit-root "$B" >/dev/null 2>&1; then
  printf 'FAIL bare agent-stack init must be rejected\n' >&2
  exit 1
fi
