#!/usr/bin/env sh
# Skill format tests: Agent Skills frontmatter, naming, and manifest sync.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
for dir in "$KIT_ROOT"/.agent-stack/skills/*/; do
  skill=$(basename -- "$dir")
  file=$dir/SKILL.md
  [ -f "$file" ] || { printf 'FAIL skill %s: SKILL.md missing\n' "$skill" >&2; FAIL=1; continue; }
  name=$(awk '/^name: /{print $2; exit}' "$file")
  [ "$name" = "$skill" ] || { printf 'FAIL skill %s: name is %s\n' "$skill" "$name" >&2; FAIL=1; }
  case "$skill" in
    *--*|-|*-) printf 'FAIL skill %s: invalid name shape\n' "$skill" >&2; FAIL=1 ;;
  esac
  desc=$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$file")
  len=$(printf '%s' "$desc" | wc -c)
  if [ -z "$desc" ] || [ "$len" -gt 1024 ]; then
    printf 'FAIL skill %s: description length %s\n' "$skill" "$len" >&2; FAIL=1
  fi
  meta_version=$(awk '/^  version: /{gsub(/"/,"",$2); print $2; exit}' "$file")
  manifest_version=$(python3 -c "import json; m=json.load(open('$KIT_ROOT/.agent-stack/skills/manifest.json')); print(next((s['version'] for s in m['skills'] if s['name']=='$skill'), ''))")
  if [ -n "$meta_version" ] && [ "$meta_version" != "$manifest_version" ]; then
    printf 'FAIL skill %s: SKILL.md version %s != manifest %s\n' "$skill" "$meta_version" "$manifest_version" >&2; FAIL=1
  fi
  lines=$(wc -l < "$file")
  if [ "$lines" -gt 500 ]; then
    printf 'FAIL skill %s: SKILL.md too long (%s lines)\n' "$skill" "$lines" >&2; FAIL=1
  fi
done
# Every manifest entry must have a directory.
for skill in project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery; do
  [ -f "$KIT_ROOT/.agent-stack/skills/$skill/SKILL.md" ] || { printf 'FAIL manifest skill %s missing directory\n' "$skill" >&2; FAIL=1; }
done
[ "$FAIL" -eq 0 ]
