#!/usr/bin/env sh
# Render-matrix tests (file rendering only): every supported runtime gets
# the intended agent format, permissions, and mandatory skill mirrors.
# Host runtime behavior (delegation, skill loading, sandbox enforcement) is
# NOT asserted here; it is covered by the manual compatibility matrix in
# docs/ADAPTER_CAPABILITIES.md and scripts/doctor.sh policy checks.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-render.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM

sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$T" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none >/dev/null 2>&1

expect() {
  file=$1; pattern=$2; label=$3
  if grep -q "$pattern" "$file" 2>/dev/null; then :;
  else printf 'FAIL render %s (%s)\n' "$label" "$file" >&2; FAIL=1; fi
}

# OpenCode format + boundaries.
expect "$T/.opencode/agents/resolver.md" '^mode: primary$' 'opencode resolver primary'
expect "$T/.opencode/agents/developer.md" '^mode: subagent$' 'opencode developer subagent'
expect "$T/.opencode/agents/designer.md" 'bash: deny' 'opencode designer denies shell'
expect "$T/.opencode/agents/design-qa.md" 'edit: deny' 'opencode qa denies edit'
expect "$T/.opencode/agents/resolver.md" 'skill: allow' 'opencode resolver skill access'
# Resolver bash allow list: the four scoped astack entries the prompt directs
# (design D9). No blanket astack allow exists, so update/upgrade/prune stay on
# the "*": ask default and still prompt a human.
for entry in run-state check doctor validate; do
  expect "$T/.opencode/agents/resolver.md" "\"astack $entry \*\": allow" \
    "opencode resolver allows astack $entry"
done
if grep -q '"astack \*": allow' "$T/.opencode/agents/resolver.md" 2>/dev/null; then
  printf 'FAIL render resolver grants blanket astack allow\n' >&2
  FAIL=1
fi
expect "$T/.opencode/agents/resolver.md" '"astack worktree audit \*": allow' 'opencode resolver allows read-only worktree audit'
if grep -q '"astack worktree cleanup \*": allow' "$T/.opencode/agents/resolver.md"; then
  printf 'FAIL render resolver must keep destructive worktree cleanup gated\n' >&2
  FAIL=1
fi
# Claude format + boundaries.
expect "$T/.claude/agents/resolver.md" '^name: resolver$' 'claude resolver name'
tools=$(awk '/^tools: /{print; exit}' "$T/.claude/agents/designer.md")
case "$tools" in *Bash*) printf 'FAIL render claude designer has Bash\n' >&2; FAIL=1 ;; esac
# Codex format + sandbox.
expect "$T/.codex/agents/design-qa.toml" 'sandbox_mode = "read-only"' 'codex qa sandbox'
expect "$T/.codex/agents/developer.toml" 'sandbox_mode = "workspace-write"' 'codex developer sandbox'
# Cursor format + read-only QA.
expect "$T/.cursor/agents/design-qa.md" 'readonly: true' 'cursor qa readonly'
# Standalone QA roles render on every platform with inherited models.
expect "$T/.opencode/agents/web-qa.md" '^model: inherit$' 'opencode web-qa inherits model'
expect "$T/.opencode/agents/mobile-qa.md" '^model: inherit$' 'opencode mobile-qa inherits model'
expect "$T/.opencode/agents/web-qa.md" 'reports/qa/' 'opencode web-qa may write qa reports'
expect "$T/.codex/agents/web-qa.toml" 'sandbox_mode = "workspace-write"' 'codex web-qa sandbox'
expect "$T/.codex/agents/mobile-qa.toml" 'sandbox_mode = "workspace-write"' 'codex mobile-qa sandbox'
expect "$T/.claude/agents/mobile-qa.md" '^name: mobile-qa$' 'claude mobile-qa name'
# QA resources are installed.
expect "$T/scripts/qa/ask-jev.ts" 'TYPESAFE_API_KEY' 'qa jev helper installed'
expect "$T/scripts/mobile-qa/questions-mobile.ts" 'buildMobileQuestions' 'mobile-qa questions installed'
expect "$T/scripts/jev/action-selection.ts" 'validateActionSelection' 'shared Jev action-selection module installed'
expect "$T/scripts/jev/validate-action-selection.ts" 'fixed at 0.75' 'shared Jev validation gate installed'
# Maestro MCP (opt-in local stdio) registers on every platform.
M=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-maestro.XXXXXX")
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$M" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp linear,maestro --specs-repository OWNER/specs >/dev/null 2>&1
expect "$M/opencode.jsonc" '"maestro"' 'opencode maestro registered'
expect "$M/opencode.jsonc" '"type": "local"' 'opencode maestro is local stdio'
expect "$M/.mcp.json" '"maestro"' 'claude maestro registered'
expect "$M/.cursor/mcp.json" '"maestro"' 'cursor maestro registered'
expect "$M/.codex/config.toml" 'mcp_servers.maestro' 'codex maestro registered'
rm -rf "$M"
# Mandatory skill mirrors resolve for every enabled platform.
for skill in project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery astack-ops typesafe-jev; do
  for mirror in ".opencode/skills/$skill/SKILL.md" ".claude/skills/$skill/SKILL.md" ".agents/skills/$skill/SKILL.md" ".cursor/skills/$skill/SKILL.md"; do
    cmp -s "$T/.agent-stack/skills/$skill/SKILL.md" "$T/$mirror" \
      || { printf 'FAIL render mirror %s\n' "$mirror" >&2; FAIL=1; }
  done
done

# Single-platform installs write only that host's skill root
# (spec skill-mirror-dedup: mirrors only for enabled hosts).
S=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-single.XXXXXX")
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$S" --kit-root "$KIT_ROOT" --platforms opencode --mcp none >/dev/null 2>&1
[ -d "$S/.opencode/skills" ] || { printf 'FAIL render opencode-only missing .opencode/skills\n' >&2; FAIL=1; }
for absent in .claude/skills .agents/skills .cursor/skills; do
  if [ -e "$S/$absent" ]; then
    printf 'FAIL render opencode-only created %s\n' "$absent" >&2
    FAIL=1
  fi
done
rm -rf "$S"
# A disabled host leaves no residue (spec skill-mirror-dedup): after a
# re-run without claude, `setup check` reports the stale root as removable
# and `prune` removes the managed skill copies its manifest recorded.
R=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-stale.XXXXXX")
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$R" --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none >/dev/null 2>&1
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$R" --kit-root "$KIT_ROOT" --platforms opencode,codex,cursor --mcp none >/dev/null 2>&1
if sh "$KIT_ROOT/scripts/setup-agent-stack.sh" check --root "$R" --kit-root "$KIT_ROOT" >"$R/check.log" 2>&1; then
  printf 'FAIL render setup check passes with stale .claude/skills residue\n' >&2
  FAIL=1
fi
expect "$R/check.log" 'stale .*claude/skills' 'check reports stale claude skill root'
sh "$KIT_ROOT/scripts/setup-agent-stack.sh" prune --root "$R" --kit-root "$KIT_ROOT" >"$R/prune.log" 2>&1
expect "$R/prune.log" 'pruned .*/.claude/skills/' 'prune removes stale claude skill copies'
if [ -e "$R/.claude/skills/project-context/SKILL.md" ]; then
  printf 'FAIL render prune left .claude/skills/project-context/SKILL.md\n' >&2
  FAIL=1
fi
if grep -q 'claude/skills' "$R/.agent-stack/generated.manifest" 2>/dev/null; then
  printf 'FAIL render manifest still records .claude/skills after prune\n' >&2
  FAIL=1
fi
rm -rf "$R"

[ "$FAIL" -eq 0 ]
