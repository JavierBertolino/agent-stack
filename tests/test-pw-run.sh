#!/usr/bin/env sh
# pw-run.sh behaviour: the wrapper must hand the browser MCP a sandboxed
# Chromium (Playwright's chromiumSandbox defaults to false) without changing
# any other part of the command contract. The systemd scope itself is host
# integration and is not asserted here (PW_SCOPE=0 keeps the test portable).
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
PW_RUN="$KIT_ROOT/.agent-stack/resources/web-qa/pw-run.sh"
FAIL=0

fail() {
  printf 'FAIL pw-run %s\n' "$1" >&2
  FAIL=1
}

# Runs the wrapper without the scope, clears any inherited value the wrapper
# might read, and prints the resulting value of one variable ("-" when unset).
value_of() {
  var=$1
  shift
  env -u PW_SANDBOX -u PW_BROWSER \
      -u PLAYWRIGHT_MCP_SANDBOX -u PLAYWRIGHT_MCP_BROWSER \
      "$@" PW_SCOPE=0 "$PW_RUN" env |
    sed -n "s/^$var=//p"
}

[ -f "$PW_RUN" ] || { printf 'FAIL pw-run wrapper missing (%s)\n' "$PW_RUN" >&2; exit 1; }
sh -n "$PW_RUN" || fail 'wrapper is not valid sh'

# Sandbox on by default, so a renderer compromise does not reach the host.
value=$(value_of PLAYWRIGHT_MCP_SANDBOX)
[ "$value" = "1" ] || fail "sandbox not enabled by default (got '${value}')"

# Explicit opt-out, and an explicit caller choice, both win.
value=$(value_of PLAYWRIGHT_MCP_SANDBOX PW_SANDBOX=0)
[ -z "$value" ] || fail "PW_SANDBOX=0 did not disable the sandbox (got '${value}')"

value=$(value_of PLAYWRIGHT_MCP_SANDBOX PLAYWRIGHT_MCP_SANDBOX=0)
[ "$value" = "0" ] || fail "caller value was overwritten (got '${value}')"

# Browser channel: opt-in only, never guessed.
value=$(value_of PLAYWRIGHT_MCP_BROWSER)
[ -z "$value" ] || fail "browser channel set without PW_BROWSER (got '${value}')"

value=$(value_of PLAYWRIGHT_MCP_BROWSER PW_BROWSER=chrome)
[ "$value" = "chrome" ] || fail "PW_BROWSER not forwarded to the MCP (got '${value}')"

value=$(value_of PLAYWRIGHT_MCP_SANDBOX PW_BROWSER=chrome)
[ "$value" = "1" ] || fail "PW_BROWSER dropped the sandbox default"

# The wrapper stays transparent: arguments verbatim, exit code untouched.
value=$(env -u PW_SANDBOX PW_SCOPE=0 "$PW_RUN" sh -c 'printf %s "$1"' _ 'two words')
[ "$value" = "two words" ] || fail "arguments were not passed through (got '${value}')"

rc=0
PW_SCOPE=0 "$PW_RUN" sh -c 'exit 7' || rc=$?
[ "$rc" -eq 7 ] || fail "exit code not passed through (got $rc)"

[ "$FAIL" -eq 0 ] || exit 1
printf 'pw-run: sandbox on by default, channel opt-in, command transparent\n'
