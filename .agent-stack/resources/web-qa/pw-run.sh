#!/bin/sh
# Run a browser-driven command in its own memory-capped systemd scope.
#
# Why: an interactive terminal session (foot -> herdr -> panes -> agents ->
# Playwright -> Chromium) all shares one systemd cgroup. When systemd-oomd
# fires, it kills the biggest cgroup, which is that whole terminal scope, and
# the terminal window disappears together with every running agent. Browsers
# are the usual trigger. Putting the browser in its own capped cgroup means an
# OOM event kills the browser, not the session.
#
# Usage:
#   scripts/qa/pw-run.sh npx playwright test
#   scripts/qa/pw-run.sh npx -y @playwright/mcp@latest --headless --isolated
#
# Tunables (environment):
#   PW_SCOPE_SLICE   slice to join (default app-playwright.slice)
#   PW_MEMORY_HIGH   soft limit, throttle before killing (default 6G)
#   PW_MEMORY_MAX    hard limit, cgroup-local OOM (default 7G)
#   PW_SWAP_MAX      swap limit for the scope (default 2G)
#   PW_SCOPE         set to 0 to skip the scope and exec directly
#
# Outside a systemd user session (macOS, containers, CI) the command runs
# unchanged, so callers stay portable.
set -eu

slice=${PW_SCOPE_SLICE:-app-playwright.slice}
high=${PW_MEMORY_HIGH:-6G}
max=${PW_MEMORY_MAX:-7G}
swap=${PW_SWAP_MAX:-2G}

if [ "${PW_SCOPE:-1}" != "0" ] &&
   command -v systemd-run >/dev/null 2>&1 &&
   [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  exec systemd-run --user --scope --quiet \
    --slice="$slice" \
    -p MemoryHigh="$high" \
    -p MemoryMax="$max" \
    -p MemorySwapMax="$swap" \
    -- "$@"
fi

exec "$@"
