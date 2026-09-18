#!/usr/bin/env sh
# update-agent-stack.sh — update the globally installed Agent Stack CLI/kit.
#
# `astack update` updates the installed CLI and kit (versioned, atomic,
# rollback-friendly). It never touches the current project; use
# `astack upgrade` to migrate a project to the installed kit.
#
# Usage: update-agent-stack.sh [--kit-root PATH] [--check]
#        [--version TAG] [--repo OWNER/REPO]
#
# Env overrides (useful for tests and mirrors):
#   ASTACK_HOME          Install base (default: derived from --kit-root).
#   ASTACK_REPO          GitHub repository (default: JavierBertolino/agent-stack).
#   ASTACK_API_URL       GitHub API base (default: https://api.github.com).
#   ASTACK_RELEASE_BASE  Local directory with VERSION + astack.tar.gz +
#                        astack.tar.gz.sha256 (skips the network; for tests).
set -eu

KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK=0
PINNED=
REPO=${ASTACK_REPO:-JavierBertolino/agent-stack}
API_URL=${ASTACK_API_URL:-https://api.github.com}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kit-root) KIT_ROOT=$2; shift ;;
    --kit-root=*) KIT_ROOT=${1#--kit-root=} ;;
    --check) CHECK=1 ;;
    --version) PINNED=$2; shift ;;
    --version=*) PINNED=${1#--version=} ;;
    --repo) REPO=$2; shift ;;
    --repo=*) REPO=${1#--repo=} ;;
    -h|--help)
      printf '%s\n' "Usage: update-agent-stack.sh [--kit-root PATH] [--check] [--version TAG] [--repo OWNER/REPO]"
      exit 0 ;;
    *) printf 'update-agent-stack.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

die() { printf '%s\n' "update-agent-stack.sh: $*" >&2; exit 1; }

kit_version() {
  if [ -f "$KIT_ROOT/VERSION" ]; then
    awk 'NR == 1 { print $1; exit }' "$KIT_ROOT/VERSION"
  else
    awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' \
      "$KIT_ROOT/.agent-stack/defaults.conf" 2>/dev/null || true
  fi
}

install_base() {
  if [ -n "${ASTACK_HOME:-}" ]; then
    printf '%s\n' "$ASTACK_HOME"
    return 0
  fi
  parent=$(dirname -- "$KIT_ROOT")
  if [ "$(basename -- "$parent")" = versions ]; then
    dirname -- "$parent"
    return 0
  fi
  return 1
}

strip_v() {
  case "$1" in
    v*) printf '%s\n' "${1#v}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

latest_tag() {
  if [ -n "${ASTACK_RELEASE_BASE:-}" ]; then
    [ -f "$ASTACK_RELEASE_BASE/VERSION" ] \
      || die "release base has no VERSION file: $ASTACK_RELEASE_BASE"
    tag=$(awk 'NR == 1 { print $1; exit }' "$ASTACK_RELEASE_BASE/VERSION")
    [ -n "$tag" ] || die "release base VERSION is empty"
    printf 'v%s\n' "$(strip_v "$tag")"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || die 'curl is required to check for updates'
  response=$(curl -fsSL --max-time 20 "$API_URL/repos/$REPO/releases/latest" 2>/dev/null) \
    || die "could not reach $API_URL/repos/$REPO/releases/latest (check your network)"
  tag=$(printf '%s' "$response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') \
    || true
  [ -n "$tag" ] || die 'could not parse the latest release tag'
  printf '%s\n' "$tag"
}

CURRENT=$(kit_version)
[ -n "$CURRENT" ] || die "could not determine the installed version from $KIT_ROOT"

if [ -n "$PINNED" ]; then
  TAG=$PINNED
else
  TAG=$(latest_tag)
fi
LATEST=$(strip_v "$TAG")

if [ "$CHECK" = 1 ]; then
  if [ "$LATEST" = "$CURRENT" ]; then
    printf 'Agent Stack %s is current\n' "$CURRENT"
    printf 'Current version: %s\n' "$CURRENT"
  else
    printf 'Agent Stack %s is available.\n' "$LATEST"
    printf 'Current version: %s\n' "$CURRENT"
  fi
  exit 0
fi

if [ "$LATEST" = "$CURRENT" ] && [ -z "$PINNED" ]; then
  printf 'Agent Stack %s is current\n' "$CURRENT"
  exit 0
fi

BASE=$(install_base) || die "this copy is not a versioned install; reinstall with: curl -fsSL https://github.com/$REPO/releases/latest/download/install.sh | sh"
case "$BASE" in
  /*) ;;
  *) die "install base must be absolute: $BASE" ;;
esac

printf '\n%s\n' 'Agent Stack update'
printf 'Current version: %s\n' "$CURRENT"
printf 'Latest version:  %s\n' "$LATEST"
printf '\n'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/astack-update.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ -n "${ASTACK_RELEASE_BASE:-}" ]; then
  cp "$ASTACK_RELEASE_BASE/astack.tar.gz" "$WORK/astack.tar.gz" \
    || die "release base has no astack.tar.gz: $ASTACK_RELEASE_BASE"
  cp "$ASTACK_RELEASE_BASE/astack.tar.gz.sha256" "$WORK/astack.tar.gz.sha256" \
    || die "release base has no astack.tar.gz.sha256: $ASTACK_RELEASE_BASE"
else
  printf 'Downloading Agent Stack %s...\n' "$LATEST"
  command -v curl >/dev/null 2>&1 || die 'curl is required to download updates'
  curl -fsSL --max-time 120 \
    "https://github.com/$REPO/releases/download/$TAG/astack.tar.gz" \
    -o "$WORK/astack.tar.gz" || die "download failed for $TAG"
  curl -fsSL --max-time 60 \
    "https://github.com/$REPO/releases/download/$TAG/astack.tar.gz.sha256" \
    -o "$WORK/astack.tar.gz.sha256" || die "checksum download failed for $TAG"
fi

printf 'Verifying checksum...\n'
(cd "$WORK" && {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c astack.tar.gz.sha256 >/dev/null 2>&1
  else
    shasum -a 256 -c astack.tar.gz.sha256 >/dev/null 2>&1
  fi
}) || die 'checksum verification failed; aborting update'

printf 'Installing...\n'
mkdir -p "$BASE/versions"
TARGET=$BASE/versions/$LATEST
if [ -d "$TARGET" ]; then
  rm -rf "$WORK/old-target"
  mv "$TARGET" "$WORK/old-target"
fi
mkdir -p "$TARGET"
tar -xzf "$WORK/astack.tar.gz" -C "$TARGET" || die 'could not extract the release archive'

# Sanity check before switching.
for script in setup-agent-stack.sh doctor.sh upgrade-agent-stack.sh update-agent-stack.sh; do
  [ -f "$TARGET/scripts/$script" ] || die "release archive is missing scripts/$script"
  sh -n "$TARGET/scripts/$script" || die "sanity check failed for scripts/$script"
done
[ -f "$TARGET/.agent-stack/defaults.conf" ] || die 'release archive is missing .agent-stack/defaults.conf'

# Switch current. `mv` over an existing symlink-to-directory would move the
# new link inside the target on some platforms, so remove first, then move.
ln -sfn "versions/$LATEST" "$BASE/current.new"
rm -f "$BASE/current"
mv -f "$BASE/current.new" "$BASE/current"

# Refresh the bin dispatcher when it points at this install base.
printf '\n%s\n' "✓ Agent Stack updated to $LATEST"

if [ -f "$PWD/.agent-stack/.kit-version" ]; then
  project_version=$(cat "$PWD/.agent-stack/.kit-version")
  if [ "$project_version" != "$LATEST" ]; then
    printf '\n%s\n' "This project was initialized with $project_version."
    printf '%s\n' 'Run `astack upgrade` to update the current project.'
  fi
fi

trap - EXIT INT TERM
rm -rf "$WORK"
