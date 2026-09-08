#!/usr/bin/env sh
# Global-install tests: install.sh --global puts a working `agent-stack`
# dispatcher on <prefix>/bin that operates on the current directory.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
P=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-prefix.XXXXXX")
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-gproj.XXXXXX")
trap 'rm -rf "$P" "$T"' EXIT INT TERM

sh "$KIT_ROOT/install.sh" --global --prefix="$P" >/dev/null 2>&1 \
  || { printf 'FAIL global install\n' >&2; FAIL=1; }
[ -x "$P/bin/agent-stack" ] || { printf 'FAIL dispatcher missing\n' >&2; FAIL=1; }
[ "$("$P/bin/agent-stack" --version)" = "$(awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' "$KIT_ROOT/.agent-stack/defaults.conf")" ] \
  || { printf 'FAIL version mismatch\n' >&2; FAIL=1; }

(cd "$T" && PATH="$P/bin:$PATH" agent-stack init --platforms opencode --mcp none >/dev/null 2>&1) \
  || { printf 'FAIL dispatcher init\n' >&2; FAIL=1; }
[ -f "$T/.opencode/agents/resolver.md" ] || { printf 'FAIL init output missing\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" agent-stack check >/dev/null 2>&1) \
  || { printf 'FAIL dispatcher check\n' >&2; FAIL=1; }

[ "$FAIL" -eq 0 ]
