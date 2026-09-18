#!/usr/bin/env sh
# Global-install tests: install.sh --global puts a working `astack`
# executable on <prefix>/bin (versioned layout) plus an unadvertised
# `agent-stack` backwards-compatibility alias.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
EXPECTED=$(awk 'NR == 1 { print $1; exit }' "$KIT_ROOT/VERSION")
FAIL=0
P=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-prefix.XXXXXX")
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-gproj.XXXXXX")
trap 'rm -rf "$P" "$T"' EXIT INT TERM

sh "$KIT_ROOT/install.sh" --global --prefix="$P" >/dev/null 2>&1 \
  || { printf 'FAIL global install\n' >&2; FAIL=1; }
[ -x "$P/bin/astack" ] || { printf 'FAIL astack executable missing\n' >&2; FAIL=1; }
[ ! -L "$P/bin/astack" ] || { printf 'FAIL astack must be the real executable, not a symlink\n' >&2; FAIL=1; }
[ -L "$P/bin/agent-stack" ] || { printf 'FAIL agent-stack compat alias missing\n' >&2; FAIL=1; }
[ -L "$P/share/astack/current" ] || { printf 'FAIL current symlink missing\n' >&2; FAIL=1; }
[ -d "$P/share/astack/versions/$EXPECTED" ] || { printf 'FAIL versioned kit dir missing\n' >&2; FAIL=1; }
[ "$("$P/bin/astack" --version)" = "$EXPECTED" ] \
  || { printf 'FAIL astack version mismatch\n' >&2; FAIL=1; }
[ "$("$P/bin/agent-stack" --version)" = "$EXPECTED" ] \
  || { printf 'FAIL compat alias version mismatch\n' >&2; FAIL=1; }

(cd "$T" && PATH="$P/bin:$PATH" astack init --platforms opencode --mcp none >/dev/null 2>&1) \
  || { printf 'FAIL dispatcher init\n' >&2; FAIL=1; }
[ -f "$T/.opencode/agents/resolver.md" ] || { printf 'FAIL init output missing\n' >&2; FAIL=1; }
[ "$(cat "$T/.agent-stack/.kit-version")" = "$EXPECTED" ] \
  || { printf 'FAIL .kit-version not recorded\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" astack check >/dev/null 2>&1) \
  || { printf 'FAIL dispatcher check\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" astack doctor >/dev/null 2>&1) \
  || { printf 'FAIL dispatcher doctor\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" astack auth jev --validate-only 2>&1 | grep -q 'TYPESAFE_API_KEY is not set') \
  || { printf 'FAIL astack auth dispatch\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" astack upgrade --check >/dev/null 2>&1) \
  || { printf 'FAIL dispatcher upgrade --check on clean project\n' >&2; FAIL=1; }

[ "$FAIL" -eq 0 ]
