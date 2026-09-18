#!/usr/bin/env sh
# doctor.sh — diagnostics for public Agent Stack users.
# Usage: scripts/doctor.sh [--root PATH] [--kit-root PATH]
# Exit 0 when all required checks pass; exit 1 with visible failures otherwise.
# Every failure prints a remediation command.

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

kit_version() {
  if [ -f "$KIT_ROOT/VERSION" ]; then
    awk 'NR == 1 { print $1; exit }' "$KIT_ROOT/VERSION"
  else
    awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' \
      "$KIT_ROOT/.agent-stack/defaults.conf" 2>/dev/null || true
  fi
}

pass() { printf '  pass %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAIL=1; }
info() { printf '  - %s\n' "$1"; }
check_ok() { printf '  ok %s\n' "$1"; }
remediate() { printf '    Run: %s\n' "$1"; }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else cksum "$1" | awk '{print $1 ":" $2}'; fi
}

get_config() {
  key=$1
  fallback=$2
  file=$ROOT/.agent-stack/config.conf
  [ -f "$file" ] || { printf '%s\n' "$fallback"; return 0; }
  value=$(awk -F= -v wanted="$key" '
    $1 == wanted {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$file")
  if [ -n "$value" ]; then printf '%s\n' "$value"; else printf '%s\n' "$fallback"; fi
}

jev_env_value() {
  key=$1
  for candidate in "${XDG_CONFIG_HOME:-$HOME/.config}/astack/env" \
                   "${XDG_CONFIG_HOME:-$HOME/.config}/agent-stack/env"; do
    [ -f "$candidate" ] || continue
    value=$(awk -F= -v wanted="$key" '
      $1 == wanted {
        value = substr($0, index($0, "=") + 1)
        sub(/^[[:space:]]*/, "", value)
        sub(/[[:space:]]*$/, "", value)
        print value
        exit
      }
    ' "$candidate")
    if [ -n "$value" ]; then return 0; fi
  done
  return 1
}

VERSION=$(kit_version)
printf '\nAgent Stack %s\n' "${VERSION:-unknown}"
printf '\nEnvironment\n'

# --- Dependencies ---
for cmd in git node python3 gh openspec; do
  if command -v "$cmd" >/dev/null 2>&1; then
    check_ok "command $cmd available"
  else
    case "$cmd" in
      node|gh|python3)
        info "command $cmd missing (needed for MCP merge / publication)"
        WARN=$((WARN + 1))
        ;;
      openspec)
        fail "command openspec missing (specify/apply stages blocked)"
        remediate "install openspec: https://github.com/Fission-AI/OpenSpec"
        ;;
      *) fail "command $cmd missing" ;;
    esac
  fi
done

# --- Project ---
printf '\nProject\n'
for role in resolver designer design-qa developer web-qa mobile-qa; do
  if [ -f "$KIT_ROOT/.agent-stack/roles/$role.md" ]; then check_ok "kit role $role";
  else fail "kit role $role missing"; fi
done

SKILLS="project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery"
skills_ok=1
for skill in $SKILLS; do
  file=$KIT_ROOT/.agent-stack/skills/$skill/SKILL.md
  if [ ! -f "$file" ]; then fail "kit skill $skill missing"; skills_ok=0; continue; fi
  name=$(awk '/^name: /{print $2; exit}' "$file")
  desc=$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$file")
  if [ "$name" != "$skill" ] || [ -z "$desc" ]; then
    fail "kit skill $skill frontmatter invalid (name=$name)"; skills_ok=0
  fi
done
if [ -f "$KIT_ROOT/.agent-stack/skills/manifest.json" ]; then check_ok "skill manifest";
else fail "skill manifest missing"; skills_ok=0; fi
for contract in handoff.schema.json report.schema.json run-state.schema.json event.schema.json; do
  if [ -f "$KIT_ROOT/.agent-stack/contracts/$contract" ]; then check_ok "contract $contract";
  else fail "contract $contract missing"; skills_ok=0; fi
done

if [ -f "$ROOT/.agent-stack/config.conf" ]; then
  check_ok "project config.conf"
else
  fail "Agent Stack is not initialized in this directory"
  remediate "astack init"
fi

if [ -f "$ROOT/.agent-stack/config.conf" ]; then
  check_ok "configuration valid"
  if [ -f "$KIT_ROOT/.agent-stack/defaults.conf" ]; then
    while IFS='=' read -r key _value; do
      case "$key" in ''|\#*) continue ;; esac
      if ! awk -F= -v wanted="$key" '$1 == wanted { found=1; exit } END { exit(found ? 0 : 1) }' "$ROOT/.agent-stack/config.conf"; then
        info "config.conf missing key $key (new kit default; add it explicitly if needed)"
        WARN=$((WARN + 1))
      fi
    done < "$KIT_ROOT/.agent-stack/defaults.conf"
    check_ok "config keys compared against kit defaults"
  fi
fi

if [ -f "$ROOT/.agent-stack/generated.manifest" ]; then
  check_ok "generated files synchronized"
else
  info "no generated manifest (run 'astack sync' after init)"
fi
[ "$skills_ok" = 1 ] && check_ok "skills valid" || true
check_ok "contracts valid"

if command -v openspec >/dev/null 2>&1; then
  if [ -f "$ROOT/openspec.yaml" ] || [ -d "$ROOT/openspec" ]; then
    check_ok "OpenSpec configuration valid"
  else
    info "OpenSpec not initialized in this project yet"
  fi
fi

# Governance status: missing | scaffold-only | draft | reviewed
for guide in UX_AGENTS UI_AGENTS; do
  file=$ROOT/$guide.md
  if [ ! -f "$file" ]; then info "governance $guide: missing"; WARN=$((WARN + 1)); continue; fi
  if grep -q 'Fill this file with project-specific' "$file" 2>/dev/null; then
    info "governance $guide: scaffold-only (run the governance-bootstrap skill)"
    WARN=$((WARN + 1))
  elif [ -f "$ROOT/.agent-stack/context/manifest.json" ]; then
    if grep -q '"reviewStatus": "reviewed"' "$ROOT/.agent-stack/context/manifest.json" 2>/dev/null; then
      check_ok "governance $guide: reviewed"
    else
      info "governance $guide: draft (awaiting review)"
      WARN=$((WARN + 1))
    fi
  else
    info "governance $guide: draft (unreviewed, no provenance manifest)"
    WARN=$((WARN + 1))
  fi
done

# Skill mirrors: presence + collision detection (differing hashes = collision)
for skill in $SKILLS; do
  canon=$ROOT/.agent-stack/skills/$skill/SKILL.md
  [ -f "$canon" ] || { info "project skill $skill not installed"; WARN=$((WARN + 1)); continue; }
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
      remediate "astack sync"
    fi
  done
  words=$(printf '%s' "$seen" | wc -w)
  if [ "$words" -gt 1 ]; then
    fail "skill collision $skill (mirrors disagree with each other)"
    remediate "astack sync"
  else
    check_ok "skill mirrors $skill consistent"
  fi
done

# Policy audit: policy (neutral prompts) is distinct from enforcement (host
# permissions). Fail closed on required boundaries; never claim equivalent
# protection an adapter cannot provide. Only existing files are audited.
if [ -f "$ROOT/.opencode/agents/resolver.md" ]; then
  if grep -q 'skill: allow' "$ROOT/.opencode/agents/resolver.md"; then
    check_ok "policy opencode resolver retains Skill access"
  else
    fail "policy opencode resolver lost Skill access"
  fi
  if grep -q '"\*": allow' "$ROOT/.opencode/agents/resolver.md"; then
    fail "policy opencode resolver grants overly broad shell patterns"
  else
    check_ok "policy opencode resolver shell scope looks bounded"
  fi
fi
if [ -f "$ROOT/.opencode/agents/designer.md" ]; then
  if grep -q 'bash: deny' "$ROOT/.opencode/agents/designer.md"; then
    check_ok "policy opencode designer denies shell"
  else
    fail "policy opencode designer must deny shell"
  fi
fi
if [ -f "$ROOT/.opencode/agents/design-qa.md" ]; then
  if grep -q 'edit: deny' "$ROOT/.opencode/agents/design-qa.md" && grep -q 'bash: deny' "$ROOT/.opencode/agents/design-qa.md"; then
    check_ok "policy opencode design-qa is read-only"
  else
    fail "policy opencode design-qa must deny edit and shell"
  fi
fi
if [ -f "$ROOT/.claude/agents/designer.md" ]; then
  tools=$(awk '/^tools: /{print; exit}' "$ROOT/.claude/agents/designer.md")
  case "$tools" in
    *Bash*) fail "policy claude designer tools must exclude Bash ($tools)" ;;
    *) check_ok "policy claude designer tools exclude Bash" ;;
  esac
fi
if [ -f "$ROOT/.claude/agents/design-qa.md" ]; then
  tools=$(awk '/^tools: /{print; exit}' "$ROOT/.claude/agents/design-qa.md")
  case "$tools" in
    *Write*|*Edit*|*Bash*) fail "policy claude design-qa must stay read-only ($tools)" ;;
    *) check_ok "policy claude design-qa is read-only" ;;
  esac
fi
if [ -f "$ROOT/.codex/agents/design-qa.toml" ]; then
  if grep -q 'sandbox_mode = "read-only"' "$ROOT/.codex/agents/design-qa.toml"; then
    check_ok "policy codex design-qa sandbox is read-only"
  else
    fail "policy codex design-qa sandbox must be read-only"
  fi
fi
if [ -f "$ROOT/.cursor/agents/design-qa.md" ]; then
  if grep -q 'readonly: true' "$ROOT/.cursor/agents/design-qa.md"; then
    check_ok "policy cursor design-qa is read-only"
  else
    fail "policy cursor design-qa must be marked readonly"
  fi
fi

# --- Integrations ---
printf '\nIntegrations\n'

# Jev status (warning only — installing Agent Stack never fails for this).
jev_provider=$(get_config JEV_PROVIDER none)
jev_ok=0
jev_label=
if [ -n "${TYPESAFE_API_KEY:-}" ] || jev_env_value TYPESAFE_API_KEY; then jev_ok=1; jev_label='TypeSafe direct'; fi
if [ -n "${AI_GATEWAY_API_KEY:-}" ] || jev_env_value AI_GATEWAY_API_KEY; then jev_ok=1; jev_label='Vercel AI Gateway'; fi
if [ -n "${JEV_GATEWAY_API_KEY:-}" ] || jev_env_value JEV_GATEWAY_API_KEY; then jev_ok=1; jev_label='gateway'; fi
if [ "$jev_ok" = 1 ]; then
  check_ok "Jev: ${jev_label:-$jev_provider}"
else
  # Warning only: installing Agent Stack never fails for missing Jev.
  info "Jev credentials are missing"
  remediate "astack auth jev"
  WARN=$((WARN + 1))
fi

if [ "$(get_config MCP_LINEAR_ENABLED 0)" = 1 ]; then check_ok "Linear configured"; else info "Linear not configured"; fi
if [ "$(get_config MCP_TRELLO_ENABLED 0)" = 1 ]; then check_ok "Trello configured"; else info "Trello not configured"; fi
if [ "$(get_config MCP_MAESTRO_ENABLED 0)" = 1 ]; then check_ok "Maestro configured"; else info "Maestro not configured"; fi

# --- Updates ---
printf '\nUpdates\n'
if [ -n "$VERSION" ] && [ -f "$ROOT/.agent-stack/.kit-version" ]; then
  project_version=$(cat "$ROOT/.agent-stack/.kit-version")
  if [ "$project_version" = "$VERSION" ]; then
    check_ok "Agent Stack $VERSION is current"
  else
    info "project uses $project_version, installed kit is $VERSION (run 'astack upgrade')"
    WARN=$((WARN + 1))
  fi
elif [ -n "$VERSION" ]; then
  check_ok "Agent Stack $VERSION is current"
fi

# Fresh-worktree reminder: uncommitted setup files do not travel
if [ -d "$ROOT/.git" ] && command -v git >/dev/null 2>&1; then
  if git -C "$ROOT" status --porcelain 2>/dev/null | grep -q '^\?\?.*\.agent-stack/skills/'; then
    info "uncommitted skills under .agent-stack/skills/ will not appear in fresh worktrees until committed"
    WARN=$((WARN + 1))
  fi
fi

printf '\n'
if [ "$FAIL" -gt 0 ]; then printf 'doctor: %s failure(s)\n' "$FAIL" >&2; exit 1; fi
if [ "$WARN" -gt 0 ]; then printf 'Everything looks usable (%s note(s) above).\n' "$WARN"; else printf 'Everything looks good.\n'; fi
