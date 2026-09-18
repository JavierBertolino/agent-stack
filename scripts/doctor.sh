#!/usr/bin/env sh
# doctor.sh — dependencies, drift, and capability checks for Agent Stack.
# Usage: scripts/doctor.sh [--root PATH] [--kit-root PATH]
# Exit 0 when all required checks pass; exit 1 with visible failures otherwise.

set -eu

ROOT=$(pwd)
KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FAIL=0
WARN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT=$2; shift ;;
    --kit-root) KIT_ROOT=$2; shift ;;
    -h|--help)
      printf '%s\n' "Usage: doctor.sh [--root PATH] [--kit-root PATH]"
      exit 0 ;;
    *) printf 'doctor.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

pass() { printf 'ok %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAIL=1; }
warn() { printf 'warn %s\n' "$1"; WARN=$((WARN + 1)); }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else cksum "$1" | awk '{print $1 ":" $2}'; fi
}

# --- Dependencies ---
for cmd in git node gh openspec; do
  if command -v "$cmd" >/dev/null 2>&1; then pass "command $cmd available";
  else
    case "$cmd" in
      node|gh) warn "command $cmd missing (needed for MCP merge / publication)" ;;
      openspec) fail "command openspec missing (specify/apply stages blocked)" ;;
      *) fail "command $cmd missing" ;;
    esac
  fi
done

# --- Kit sources ---
for role in resolver designer design-qa developer web-qa mobile-qa; do
  if [ -f "$KIT_ROOT/.agent-stack/roles/$role.md" ]; then pass "kit role $role";
  else fail "kit role $role missing"; fi
done

SKILLS="project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery"
for skill in $SKILLS; do
  file=$KIT_ROOT/.agent-stack/skills/$skill/SKILL.md
  if [ ! -f "$file" ]; then fail "kit skill $skill missing"; continue; fi
  name=$(awk '/^name: /{print $2; exit}' "$file")
  desc=$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$file")
  if [ "$name" = "$skill" ] && [ -n "$desc" ]; then pass "kit skill $skill frontmatter";
  else fail "kit skill $skill frontmatter invalid (name=$name)"; fi
done

if [ -f "$KIT_ROOT/.agent-stack/skills/manifest.json" ]; then pass "skill manifest";
else fail "skill manifest missing"; fi
for contract in handoff.schema.json report.schema.json run-state.schema.json event.schema.json; do
  if [ -f "$KIT_ROOT/.agent-stack/contracts/$contract" ]; then pass "contract $contract";
  else fail "contract $contract missing"; fi
done

# --- Project state ---
if [ -f "$ROOT/.agent-stack/config.conf" ]; then pass "project config.conf";
else warn "project config.conf missing (not installed?)"; fi

# Config keys: upgrades never modify config.conf, so new kit defaults must
# be surfaced here instead of silently ignored.
if [ -f "$ROOT/.agent-stack/config.conf" ] && [ -f "$KIT_ROOT/.agent-stack/defaults.conf" ]; then
  while IFS='=' read -r key _value; do
    case "$key" in ''|\#*) continue ;; esac
    if ! awk -F= -v wanted="$key" '$1 == wanted { found=1; exit } END { exit(found ? 0 : 1) }' "$ROOT/.agent-stack/config.conf"; then
      warn "config.conf missing key $key (new kit default; add it explicitly if needed)"
    fi
  done < "$KIT_ROOT/.agent-stack/defaults.conf"
  pass "config keys compared against kit defaults"
fi

# Governance status: missing | scaffold-only | draft | reviewed
for guide in UX_AGENTS UI_AGENTS; do
  file=$ROOT/$guide.md
  if [ ! -f "$file" ]; then warn "governance $guide: missing"; continue; fi
  if grep -q 'Fill this file with project-specific' "$file" 2>/dev/null; then
    warn "governance $guide: scaffold-only (run the governance-bootstrap skill)"
  elif [ -f "$ROOT/.agent-stack/context/manifest.json" ]; then
    if grep -q '"reviewStatus": "reviewed"' "$ROOT/.agent-stack/context/manifest.json" 2>/dev/null; then
      pass "governance $guide: reviewed"
    else
      warn "governance $guide: draft (awaiting review)"
    fi
  else
    warn "governance $guide: draft (unreviewed, no provenance manifest)"
  fi
done

# Skill mirrors: presence + collision detection (differing hashes = collision)
for skill in $SKILLS; do
  canon=$ROOT/.agent-stack/skills/$skill/SKILL.md
  [ -f "$canon" ] || { warn "project skill $skill not installed"; continue; }
  seen=""
  for root in "$ROOT/.opencode/skills/$skill/SKILL.md" "$ROOT/.claude/skills/$skill/SKILL.md" "$ROOT/.agents/skills/$skill/SKILL.md" "$ROOT/.cursor/skills/$skill/SKILL.md"; do
    [ -f "$root" ] || continue
    h=$(hash_file "$root")
    case " $seen " in
      *" $h "*) ;;
      *) seen="$seen $h" ;;
    esac
    if [ "$h" != "$(hash_file "$canon")" ]; then
      fail "skill mirror drift $skill ($root differs from canonical)"
    fi
  done
  words=$(printf '%s' "$seen" | wc -w)
  if [ "$words" -gt 1 ]; then
    fail "skill collision $skill (mirrors disagree with each other)"
  else
    pass "skill mirrors $skill consistent"
  fi
done

# Policy audit: policy (neutral prompts) is distinct from enforcement (host
# permissions). Fail closed on required boundaries; never claim equivalent
# protection an adapter cannot provide. Only existing files are audited.
if [ -f "$ROOT/.opencode/agents/resolver.md" ]; then
  if grep -q 'skill: allow' "$ROOT/.opencode/agents/resolver.md"; then
    pass "policy opencode resolver retains Skill access"
  else
    fail "policy opencode resolver lost Skill access"
  fi
  if grep -q '"\*": allow' "$ROOT/.opencode/agents/resolver.md"; then
    fail "policy opencode resolver grants overly broad shell patterns"
  else
    pass "policy opencode resolver shell scope looks bounded"
  fi
fi
if [ -f "$ROOT/.opencode/agents/designer.md" ]; then
  if grep -q 'bash: deny' "$ROOT/.opencode/agents/designer.md"; then
    pass "policy opencode designer denies shell"
  else
    fail "policy opencode designer must deny shell"
  fi
fi
if [ -f "$ROOT/.opencode/agents/design-qa.md" ]; then
  if grep -q 'edit: deny' "$ROOT/.opencode/agents/design-qa.md" && grep -q 'bash: deny' "$ROOT/.opencode/agents/design-qa.md"; then
    pass "policy opencode design-qa is read-only"
  else
    fail "policy opencode design-qa must deny edit and shell"
  fi
fi
if [ -f "$ROOT/.claude/agents/designer.md" ]; then
  tools=$(awk '/^tools: /{print; exit}' "$ROOT/.claude/agents/designer.md")
  case "$tools" in
    *Bash*) fail "policy claude designer tools must exclude Bash ($tools)" ;;
    *) pass "policy claude designer tools exclude Bash" ;;
  esac
fi
if [ -f "$ROOT/.claude/agents/design-qa.md" ]; then
  tools=$(awk '/^tools: /{print; exit}' "$ROOT/.claude/agents/design-qa.md")
  case "$tools" in
    *Write*|*Edit*|*Bash*) fail "policy claude design-qa must stay read-only ($tools)" ;;
    *) pass "policy claude design-qa is read-only" ;;
  esac
fi
if [ -f "$ROOT/.codex/agents/design-qa.toml" ]; then
  if grep -q 'sandbox_mode = "read-only"' "$ROOT/.codex/agents/design-qa.toml"; then
    pass "policy codex design-qa sandbox is read-only"
  else
    fail "policy codex design-qa sandbox must be read-only"
  fi
fi
if [ -f "$ROOT/.cursor/agents/design-qa.md" ]; then
  if grep -q 'readonly: true' "$ROOT/.cursor/agents/design-qa.md"; then
    pass "policy cursor design-qa is read-only"
  else
    fail "policy cursor design-qa must be marked readonly"
  fi
fi

# Fresh-worktree reminder: uncommitted setup files do not travel
if [ -d "$ROOT/.git" ] && command -v git >/dev/null 2>&1; then
  if git -C "$ROOT" status --porcelain 2>/dev/null | grep -q '^\?\?.*\.agent-stack/skills/'; then
    warn "uncommitted skills under .agent-stack/skills/ will not appear in fresh worktrees until committed"
  fi
fi

if [ "$FAIL" -gt 0 ]; then printf 'doctor: %s failure(s)\n' "$FAIL" >&2; exit 1; fi
printf 'doctor: all required checks passed (%s warning(s))\n' "$WARN"
