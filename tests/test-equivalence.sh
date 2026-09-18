#!/usr/bin/env sh
# Equivalence tests: standalone (setup.sh) and checkout
# (scripts/setup-agent-stack.sh) installations produce equivalent outputs.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
A=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-equiv-a.XXXXXX")
B=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-equiv-b.XXXXXX")
trap 'rm -rf "$A" "$B"' EXIT INT TERM

sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$A" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none >/dev/null 2>&1
(cd "$B" && sh "$KIT_ROOT/setup.sh" init --platforms opencode,claude,codex,cursor --mcp none >/dev/null 2>&1)

# Compare relative file trees by content hash. Temp render files and
# transient logs are excluded; everything else must be byte-identical.
list_hashes() {
  root=$1
  out=$2
  paths=""
  for candidate in .agent-stack .opencode .claude .codex .cursor .agents UX_AGENTS.md UI_AGENTS.md opencode.jsonc .mcp.json; do
    [ -e "$root/$candidate" ] && paths="$paths $candidate"
  done
  # shellcheck disable=SC2086
  (cd "$root" && find $paths -type f \
    ! -name '*.log' ! -name '.models.*' ! -name '.skill.*' ! -name '.opencode.*' \
    ! -name '.claude.*' ! -name '.codex.*' ! -name '.cursor.*' ! -name '.agents.*' \
    -exec sha256sum {} + 2>/dev/null | sort -k2 >"$out")
}
list_hashes "$A" "$A.hashes"
list_hashes "$B" "$B.hashes"
if ! diff "$A.hashes" "$B.hashes" >/dev/null 2>&1; then
  printf 'FAIL standalone and checkout installs differ\n' >&2
  diff "$A.hashes" "$B.hashes" >&2 || true
  FAIL=1
fi

[ "$FAIL" -eq 0 ]
