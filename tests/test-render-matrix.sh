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
# Mandatory skill mirrors resolve for every enabled platform.
for skill in project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery; do
  for mirror in ".opencode/skills/$skill/SKILL.md" ".claude/skills/$skill/SKILL.md" ".agents/skills/$skill/SKILL.md" ".cursor/skills/$skill/SKILL.md"; do
    cmp -s "$T/.agent-stack/skills/$skill/SKILL.md" "$T/$mirror" \
      || { printf 'FAIL render mirror %s\n' "$mirror" >&2; FAIL=1; }
  done
done

[ "$FAIL" -eq 0 ]
