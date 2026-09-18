#!/usr/bin/env sh
# upgrade-agent-stack.sh — safe source-version migration for Agent Stack.
#
# Updating the kit is not the same as updating installed role sources:
# copy-if-missing preserves local edits but never propagates revised
# defaults. This script performs a three-way comparison using the base
# hashes recorded in .agent-stack/sources.manifest at install time:
#
#   project == new kit   -> up-to-date, record new base
#   project == old base  -> unchanged managed source, update safely
#   otherwise            -> user customization preserved; new kit content
#                           written to <file>.kit-new for manual merge
#
# Nothing human-owned is ever overwritten. After upgrading, run
# setup-agent-stack.sh sync to re-render platform mirrors.
#
# Usage: upgrade-agent-stack.sh [--root PATH] [--kit-root PATH] [--check]
#   --check reports pending updates/conflicts without changing anything.

set -eu

ROOT=$(pwd)
KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK=0
UPDATED=0
CONFLICTS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) ROOT=$2; shift ;;
    --kit-root) KIT_ROOT=$2; shift ;;
    --check) CHECK=1 ;;
    -h|--help)
      printf '%s\n' "Usage: upgrade-agent-stack.sh [--root PATH] [--kit-root PATH] [--check]"
      exit 0 ;;
    *) printf 'upgrade-agent-stack.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

die() { printf '%s\n' "upgrade-agent-stack.sh: $*" >&2; exit 1; }

kit_version() {
  if [ -f "$KIT_ROOT/VERSION" ]; then
    awk 'NR == 1 { print $1; exit }' "$KIT_ROOT/VERSION"
  else
    awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' \
      "$KIT_ROOT/.agent-stack/defaults.conf" 2>/dev/null || true
  fi
}

file_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    cksum "$1" | awk '{print $1 ":" $2}'
  fi
}

SOURCES_MANIFEST=$ROOT/.agent-stack/sources.manifest

base_hash() {
  relative=$1
  [ -f "$SOURCES_MANIFEST" ] || return 1
  awk -F'|' -v wanted="$relative" '$1 == wanted { print $2; found=1; exit } END { exit(found ? 0 : 1) }' "$SOURCES_MANIFEST"
}

record_base() {
  relative=$1
  hash=$2
  temporary=$(mktemp "$SOURCES_MANIFEST.XXXXXX" 2>/dev/null || mktemp "${TMPDIR:-/tmp}/sources.XXXXXX")
  if [ -f "$SOURCES_MANIFEST" ]; then
    awk -F'|' -v wanted="$relative" -v replacement="$hash" '
      BEGIN { found = 0 }
      $1 == wanted { if (!found) print wanted "|" replacement; found = 1; next }
      { print }
      END { if (!found) print wanted "|" replacement }
    ' "$SOURCES_MANIFEST" > "$temporary"
  else
    mkdir -p "$(dirname -- "$SOURCES_MANIFEST")"
    printf '%s\n' "$relative|$hash" > "$temporary"
  fi
  mv "$temporary" "$SOURCES_MANIFEST"
}

upgrade_one() {
  relative=$1
  kit_file=$KIT_ROOT/.agent-stack/$relative
  project_file=$ROOT/.agent-stack/$relative
  [ -f "$kit_file" ] || return 0
  new_hash=$(file_hash "$kit_file")

  if [ ! -e "$project_file" ]; then
    if [ "$CHECK" = 1 ]; then
      printf 'would add %s (new upstream source)\n' "$project_file"
      UPDATED=$((UPDATED + 1))
    else
      mkdir -p "$(dirname -- "$project_file")"
      cp "$kit_file" "$project_file"
      record_base "$relative" "$new_hash"
      printf 'added %s\n' "$project_file"
      UPDATED=$((UPDATED + 1))
    fi
    return 0
  fi

  project_hash=$(file_hash "$project_file")
  if [ "$project_hash" = "$new_hash" ]; then
    [ "$CHECK" = 0 ] && record_base "$relative" "$new_hash"
    return 0
  fi

  old_base=$(base_hash "$relative" 2>/dev/null || true)
  if [ -n "$old_base" ] && [ "$project_hash" = "$old_base" ]; then
    if [ "$CHECK" = 1 ]; then
      printf 'would update %s (unchanged managed source)\n' "$project_file"
      UPDATED=$((UPDATED + 1))
    else
      cp "$kit_file" "$project_file"
      record_base "$relative" "$new_hash"
      printf 'updated %s\n' "$project_file"
      UPDATED=$((UPDATED + 1))
    fi
    return 0
  fi

  if [ -z "$old_base" ]; then
    printf 'conflict, no recorded base for %s (pre-manifest install or local file); preserved %s\n' "$relative" "$project_file" >&2
  else
    printf 'conflict, preserved customized %s\n' "$project_file" >&2
  fi
  if [ "$CHECK" = 0 ]; then
    cp "$kit_file" "$project_file.kit-new"
    printf 'wrote %s.kit-new for manual merge\n' "$project_file" >&2
  fi
  CONFLICTS=$((CONFLICTS + 1))
}

[ -d "$ROOT/.agent-stack" ] || die "not an installed project: $ROOT/.agent-stack missing (run init first)"
[ -d "$KIT_ROOT/.agent-stack" ] || die "kit directory missing: $KIT_ROOT/.agent-stack"

NEW_VERSION=$(kit_version)
OLD_VERSION=$(cat "$ROOT/.agent-stack/.kit-version" 2>/dev/null || printf 'unknown')
if [ "$CHECK" = 0 ]; then
  printf '\n%s\n' 'Agent Stack project upgrade'
  printf '%s\n' "$OLD_VERSION → $NEW_VERSION"
  printf '\n'
fi

# Managed sources: roles, skills, contracts. Project config.conf is never
# modified here; missing new defaults are reported by doctor.sh instead.
for role in resolver designer design-qa developer web-qa mobile-qa; do
  upgrade_one "roles/$role.md"
done
for skill in project-context linear-workflow governance-bootstrap openspec-workflow ux-design implementation ui-review git-delivery; do
  upgrade_one "skills/$skill/SKILL.md"
done
upgrade_one "skills/manifest.json"
for contract in handoff.schema.json report.schema.json run-state.schema.json event.schema.json; do
  upgrade_one "contracts/$contract"
done

# Upstream additions not yet installed are handled by upgrade_one (added).
# Upstream removals: report files tracked in the manifest that no longer
# exist in the kit; the local copy is always preserved.
if [ -f "$SOURCES_MANIFEST" ]; then
  while IFS='|' read -r relative _hash; do
    case "$relative" in ''|\#*) continue ;; esac
    if [ ! -f "$KIT_ROOT/.agent-stack/$relative" ] && [ -e "$ROOT/.agent-stack/$relative" ]; then
      printf 'removed upstream, preserved locally: %s\n' "$ROOT/.agent-stack/$relative"
    fi
  done < "$SOURCES_MANIFEST"
fi

if [ "$CHECK" = 1 ]; then
  printf 'upgrade check: %s pending update(s), %s conflict(s)\n' "$UPDATED" "$CONFLICTS"
  [ "$UPDATED" -gt 0 ] || [ "$CONFLICTS" -gt 0 ] && exit 1
  exit 0
fi

# Managed sources: report per-file outcomes in upgrade order.
printf 'upgrade: %s updated, %s conflict(s)\n' "$UPDATED" "$CONFLICTS"
if [ "$CONFLICTS" -gt 0 ]; then
  printf '%s\n' 'Some files need a manual merge.' >&2
  printf '%s\n' 'Review the .kit-new files, merge them into your customized copies,' >&2
  printf '%s\n' 'then re-run the upgrade.' >&2
  exit 1
fi

if [ -n "$NEW_VERSION" ]; then
  printf '%s\n' "$NEW_VERSION" > "$ROOT/.agent-stack/.kit-version"
fi
printf '\n%s\n' 'No local modifications were overwritten.'
printf '\n%s\n' 'Project upgraded successfully.'
if [ "$UPDATED" -gt 0 ]; then
  printf 'next: run setup-agent-stack.sh sync --root "%s" --kit-root "%s" to re-render platform mirrors\n' "$ROOT" "$KIT_ROOT"
fi
exit 0
