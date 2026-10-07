#!/usr/bin/env sh
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
if ! command -v node >/dev/null 2>&1 || ! node -e 'const [major,minor]=process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 6) ? 0 : 1)'; then
  printf '%s\n' 'SKIP Jev tests (Node.js 22.6+ unavailable)'
  exit 0
fi
node --experimental-strip-types "$KIT_ROOT/tests/test-jev.mjs" "$KIT_ROOT"
