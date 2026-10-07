#!/usr/bin/env sh
# Prompt-size budgets: every prompt a host loads has a declared ceiling, so
# growth shows up as a number instead of creeping in silently. Budgets are
# declared once, here (spec: prompt-size-budgets).
#
# Expected to be RED for the resolver until the split (task group 3) lands:
# the neutral resolver ships at 18,412 B against its 13,800 B budget.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0

ROLE_LINES=400          # lines, every neutral role
ROLE_RESOLVER_B=13800   # bytes, .agent-stack/roles/resolver.md
ROLE_OTHER_B=7000       # bytes, every other neutral role
RENDERED_B=14900        # bytes, every rendered agent file, frontmatter included
SKILL_DESC_B=2500       # bytes, sum of description: values in skills/*/SKILL.md

# --- Neutral roles: bytes and lines ---------------------------------------
for role in "$KIT_ROOT"/.agent-stack/roles/*.md; do
  [ -f "$role" ] || continue
  name=$(basename "$role")
  bytes=$(wc -c < "$role")
  lines=$(wc -l < "$role")
  if [ "$name" = resolver.md ]; then cap=$ROLE_RESOLVER_B; else cap=$ROLE_OTHER_B; fi
  if [ "$bytes" -gt "$cap" ]; then
    printf 'FAIL role %s: %s bytes over its %s-byte budget (+%s)\n' \
      "$name" "$bytes" "$cap" "$((bytes - cap))" >&2
    FAIL=1
  fi
  if [ "$lines" -gt "$ROLE_LINES" ]; then
    printf 'FAIL role %s: %s lines over its %s-line budget (+%s)\n' \
      "$name" "$lines" "$ROLE_LINES" "$((lines - ROLE_LINES))" >&2
    FAIL=1
  fi
  printf 'budget role %-12s %s/%s B  (%s/%s lines)\n' \
    "$name" "$bytes" "$cap" "$lines" "$ROLE_LINES"
done

# --- Combined skill descriptions ------------------------------------------
desc_total=0
report=""
for skill_md in "$KIT_ROOT"/.agent-stack/skills/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  skill=$(basename "$(dirname "$skill_md")")
  desc=$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$skill_md")
  b=$(printf '%s' "$desc" | wc -c)
  desc_total=$((desc_total + b))
  report="$report
$b $skill"
done
printf 'budget skill descriptions  %s/%s B\n' "$desc_total" "$SKILL_DESC_B"
if [ "$desc_total" -gt "$SKILL_DESC_B" ]; then
  printf 'FAIL skill descriptions: total %s bytes over the %s-byte budget; largest:\n' \
    "$desc_total" "$SKILL_DESC_B" >&2
  printf '%s\n' "$report" | grep -v '^$' | sort -rn | head -3 >&2
  FAIL=1
fi

# --- Rendered agents, measured on a real install ---------------------------
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-budgets.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM
if ! sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$T" \
  --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none \
  >/dev/null 2>&1; then
  printf 'FAIL budget test: fixture install failed, rendered sizes unmeasured\n' >&2
  FAIL=1
fi

worst_file=""
worst_bytes=0
for host in .opencode/agents .claude/agents .codex/agents .cursor/agents; do
  [ -d "$T/$host" ] || continue
  for f in "$T/$host"/*; do
    [ -f "$f" ] || continue
    b=$(wc -c < "$f")
    if [ "$b" -gt "$RENDERED_B" ]; then
      printf 'FAIL rendered %s/%s: %s bytes over the %s-byte budget (+%s)\n' \
        "$host" "$(basename "$f")" "$b" "$RENDERED_B" "$((b - RENDERED_B))" >&2
      FAIL=1
      if [ "$b" -gt "$worst_bytes" ]; then
        worst_bytes=$b
        worst_file="$host/$(basename "$f")"
      fi
    fi
  done
done
if [ -n "$worst_file" ]; then
  printf 'budget rendered biggest offender: %s at %s/%s B\n' \
    "$worst_file" "$worst_bytes" "$RENDERED_B" >&2
else
  printf 'budget rendered within %s B on all platforms\n' "$RENDERED_B"
fi

[ "$FAIL" -eq 0 ]
