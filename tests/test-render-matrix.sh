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
for skill in project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery; do
  for mirror in ".opencode/skills/$skill/SKILL.md" ".claude/skills/$skill/SKILL.md" ".agents/skills/$skill/SKILL.md" ".cursor/skills/$skill/SKILL.md"; do
    cmp -s "$T/.agent-stack/skills/$skill/SKILL.md" "$T/$mirror" \
      || { printf 'FAIL render mirror %s\n' "$mirror" >&2; FAIL=1; }
  done
done

[ "$FAIL" -eq 0 ]
