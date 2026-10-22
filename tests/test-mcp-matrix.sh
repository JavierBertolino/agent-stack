#!/usr/bin/env sh
# --mcp parsing is one order-independent function: none resets, every other
# token adds, both means linear+trello and does not turn other servers off.
# Explicit --platforms/--mcp persist. Unknown values exit 1 before any write.
# Disabled managed servers are removed from host MCP files. doctor reports
# the resulting integration flags.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-mcp.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

fail() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=1
}

setup() {
  sh "$KIT_ROOT/scripts/setup-agent-stack.sh" "$@" --kit-root "$KIT_ROOT"
}

flag() {
  root=$1
  key=$2
  awk -F= -v wanted="$key" '$1 == wanted { print $2; exit }' "$root/.agent-stack/config.conf"
}

expect_flags() {
  root=$1
  linear=$2
  trello=$3
  jira=$4
  maestro=$5
  label=$6
  got=$(printf '%s%s%s%s' "$(flag "$root" MCP_LINEAR_ENABLED)" "$(flag "$root" MCP_TRELLO_ENABLED)" "$(flag "$root" MCP_JIRA_ENABLED)" "$(flag "$root" MCP_MAESTRO_ENABLED)")
  want="${linear}${trello}${jira}${maestro}"
  [ "$got" = "$want" ] || fail "$label: flags linear,trello,jira,maestro=$got want $want"
}

# Unknown values must exit 1 and create nothing.
for args in "--platforms nope --mcp none" "--platforms opencode --mcp confluence" "--platforms opencode --mcp linear,nope"; do
  # shellcheck disable=SC2086
  empty=$(mktemp -d "$WORK/empty.XXXXXX")
  if setup init --root "$empty" $args >"$empty/out.log" 2>&1; then
    fail "init $args must exit 1"
  fi
  if [ -e "$empty/.agent-stack" ] || [ -e "$empty/.opencode" ] || [ -e "$empty/.mcp.json" ]; then
    fail "init $args wrote files before rejecting the flag"
  fi
  if ! grep -q 'valid:' "$empty/out.log"; then
    fail "init $args must list valid ids"
  fi
done

# Order does not matter, including none mixed with adds.
A=$WORK/a
B=$WORK/b
mkdir -p "$A" "$B"
setup init --root "$A" --platforms opencode --mcp 'linear,none,maestro' >/dev/null 2>&1
setup init --root "$B" --platforms opencode --mcp 'none,maestro,linear' >/dev/null 2>&1
expect_flags "$A" 1 0 0 1 'linear,none,maestro'
expect_flags "$B" 1 0 0 1 'none,maestro,linear'

C=$WORK/c
D=$WORK/d
mkdir -p "$C" "$D"
setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp 'both,maestro' >/dev/null 2>&1
setup init --root "$D" --platforms opencode,claude,codex,cursor --mcp 'maestro,both' >/dev/null 2>&1
expect_flags "$C" 1 1 0 1 'both,maestro'
expect_flags "$D" 1 1 0 1 'maestro,both'

# A later single token adds. It does not turn servers off.
setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp linear >/dev/null 2>&1
expect_flags "$C" 1 1 0 1 'linear adds and keeps trello and maestro'

# none resets, then a following re-init can add one server back.
setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp none >/dev/null 2>&1
expect_flags "$C" 0 0 0 0 'none resets'
for needle in 'mcp.linear.app' 'mcp.trello.com' 'mcp.atlassian.com' 'maestro'; do
  if grep -R -q "$needle" "$C/.mcp.json" "$C/.cursor/mcp.json" "$C/opencode.jsonc" "$C/.codex/config.toml" 2>/dev/null; then
    fail "none left $needle in a host MCP file"
  fi
done

setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp trello >/dev/null 2>&1
expect_flags "$C" 0 1 0 0 'trello after none'
grep -q 'mcp.trello.com' "$C/.mcp.json" || fail 'trello missing from .mcp.json'
grep -q 'mcp.trello.com' "$C/.cursor/mcp.json" || fail 'trello missing from .cursor/mcp.json'
grep -q 'mcp.trello.com' "$C/opencode.jsonc" || fail 'trello missing from opencode.jsonc'
grep -q 'mcp.trello.com' "$C/.codex/config.toml" || fail 'trello missing from .codex/config.toml'
if grep -q 'mcp.linear.app' "$C/.mcp.json" "$C/opencode.jsonc" "$C/.cursor/mcp.json" "$C/.codex/config.toml"; then
  fail 'linear remained after it was disabled'
fi

# Jira joins the same parser: a single token registers the Atlassian server,
# `both` leaves it enabled, and `none` removes it again.
setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp jira >/dev/null 2>&1
expect_flags "$C" 0 1 1 0 'jira adds to trello'
for host in "$C/opencode.jsonc" "$C/.mcp.json" "$C/.cursor/mcp.json" "$C/.codex/config.toml"; do
  grep -q 'mcp.atlassian.com' "$host" || fail "jira missing from $host"
done
setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp both >/dev/null 2>&1
expect_flags "$C" 1 1 1 0 'both keeps jira enabled'
setup init --root "$C" --platforms opencode,claude,codex,cursor --mcp none >/dev/null 2>&1
expect_flags "$C" 0 0 0 0 'none clears jira'
for host in "$C/opencode.jsonc" "$C/.mcp.json" "$C/.cursor/mcp.json" "$C/.codex/config.toml"; do
  if grep -q 'mcp.atlassian.com' "$host" 2>/dev/null; then
    fail "none left the jira server in $host"
  fi
done

# Re-init --platforms persists even when --mcp is omitted, same as the wizard.
P=$WORK/platforms
mkdir -p "$P"
setup init --root "$P" --platforms claude >/dev/null 2>&1
[ "$(flag "$P" ENABLE_CLAUDE)" = 1 ] || fail 'ENABLE_CLAUDE not persisted'
[ "$(flag "$P" ENABLE_CURSOR)" = 0 ] || fail 'ENABLE_CURSOR should be 0 after --platforms claude'
setup init --root "$P" --platforms cursor >/dev/null 2>&1
[ "$(flag "$P" ENABLE_CURSOR)" = 1 ] || fail 'ENABLE_CURSOR not persisted on re-init'
[ "$(flag "$P" ENABLE_CLAUDE)" = 0 ] || fail 'ENABLE_CLAUDE stayed 1 after --platforms cursor'
[ -d "$P/.cursor/agents" ] || fail 'cursor agents were not written'

# Disabling Codex must leave .codex/config.toml byte-for-byte so prune can
# delete it. Turning Codex back on renders the managed server again.
file_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
X=$WORK/codex-switch
mkdir -p "$X"
setup init --root "$X" --platforms opencode,claude,codex,cursor --mcp linear >/dev/null 2>&1
recorded=$(awk -F'|' '$1 == ".codex/config.toml" { print $2; exit }' "$X/.agent-stack/generated.manifest")
[ -n "$recorded" ] || fail 'codex config was not recorded in the manifest'
setup init --root "$X" --platforms opencode --mcp linear >/dev/null 2>&1
grep -q 'mcp.linear.app' "$X/.codex/config.toml" || fail 'disabling codex rewrote config.toml before prune'
[ "$(file_sha "$X/.codex/config.toml")" = "$recorded" ] || fail 'disabling codex changed the config.toml hash'
setup prune --root "$X" >/dev/null 2>&1 || fail 'prune after disabling codex failed'
if [ -f "$X/.codex/config.toml" ]; then
  fail 'prune left an unchanged .codex/config.toml'
fi
setup check --root "$X" >/dev/null 2>&1 || fail 'check failed after pruning a disabled codex install'
setup init --root "$X" --platforms opencode,codex --mcp linear >/dev/null 2>&1
grep -q 'mcp.linear.app' "$X/.codex/config.toml" || fail 're-enabled codex config is missing linear'
setup check --root "$X" >/dev/null 2>&1 || fail 'check failed after re-enabling codex'

# A host MCP file that does not parse must fail the command.
BAD=$WORK/bad-json
mkdir -p "$BAD"
setup init --root "$BAD" --platforms opencode --mcp linear >/dev/null 2>&1
printf '%s\n' '{ this is not json' > "$BAD/opencode.jsonc"
if setup init --root "$BAD" --platforms opencode --mcp none >"$BAD/bad.log" 2>&1; then
  fail 'unparseable opencode.jsonc must make init exit nonzero'
fi
grep -q 'could not parse' "$BAD/bad.log" || fail 'unparseable MCP file must say it was left unchanged'

# doctor reports the integration state from config.
sh "$KIT_ROOT/scripts/doctor.sh" --root "$D" --kit-root "$KIT_ROOT" >"$D/doctor.log" 2>&1 || true
grep -q 'Linear configured' "$D/doctor.log" || fail 'doctor must report Linear configured'
grep -q 'Trello configured' "$D/doctor.log" || fail 'doctor must report Trello configured'
grep -q 'Maestro configured' "$D/doctor.log" || fail 'doctor must report Maestro configured'

[ "$FAIL" -eq 0 ]
