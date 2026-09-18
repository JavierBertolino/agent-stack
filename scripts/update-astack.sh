#!/usr/bin/env sh
# update-astack.sh - update the installed Agent Stack CLI/kit from GitHub Releases.
set -eu

KIT_ROOT=
CHECK_ONLY=0
REPOSITORY=${ASTACK_REPOSITORY:-JavierBertolino/agent-stack}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kit-root)
      [ "$#" -gt 1 ] || { printf 'astack update: --kit-root requires a path\n' >&2; exit 2; }
      KIT_ROOT=$2
      shift
      ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      printf '%s\n' 'Usage: astack update [--check]'
      exit 0
      ;;
    *)
      printf 'astack update: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

[ -n "$KIT_ROOT" ] || KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ -f "$KIT_ROOT/.agent-stack/defaults.conf" ] || {
  printf 'astack update: invalid kit root: %s\n' "$KIT_ROOT" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  printf 'astack update: curl is required\n' >&2
  exit 1
}
command -v tar >/dev/null 2>&1 || {
  printf 'astack update: tar is required\n' >&2
  exit 1
}

CURRENT=$(awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' "$KIT_ROOT/.agent-stack/defaults.conf")
API="https://api.github.com/repos/$REPOSITORY/releases/latest"
LATEST=$(curl -fsSL "$API" | awk -F'"' '/"tag_name"[[:space:]]*:/ { print $4; exit }' | sed 's/^v//')
[ -n "$LATEST" ] || {
  printf 'astack update: could not determine latest release\n' >&2
  exit 1
}

if [ "$CURRENT" = "$LATEST" ]; then
  printf 'astack %s is up to date\n' "$CURRENT"
  exit 0
fi

printf 'astack update available: %s -> %s\n' "$CURRENT" "$LATEST"
[ "$CHECK_ONLY" = 1 ] && exit 1

TMP=$(mktemp -d "${TMPDIR:-/tmp}/astack-update.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BASE="https://github.com/$REPOSITORY/releases/download/v$LATEST"
curl -fsSL "$BASE/astack.tar.gz" -o "$TMP/astack.tar.gz"
curl -fsSL "$BASE/astack.tar.gz.sha256" -o "$TMP/astack.tar.gz.sha256"

EXPECTED=$(awk '{print $1}' "$TMP/astack.tar.gz.sha256")
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL=$(sha256sum "$TMP/astack.tar.gz" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL=$(shasum -a 256 "$TMP/astack.tar.gz" | awk '{print $1}')
else
  printf 'astack update: sha256sum or shasum is required to verify releases\n' >&2
  exit 1
fi
[ "$EXPECTED" = "$ACTUAL" ] || {
  printf 'astack update: checksum verification failed\n' >&2
  exit 1
}

mkdir -p "$TMP/new"
tar -xzf "$TMP/astack.tar.gz" -C "$TMP/new"
[ -f "$TMP/new/.agent-stack/defaults.conf" ] || {
  printf 'astack update: release archive is invalid\n' >&2
  exit 1
}

PREFIX=$(dirname -- "$(dirname -- "$KIT_ROOT")")
BIN="$PREFIX/bin/astack"
OLD="$KIT_ROOT.previous"
rm -rf "$OLD"
mv "$KIT_ROOT" "$OLD"
if ! mv "$TMP/new" "$KIT_ROOT"; then
  mv "$OLD" "$KIT_ROOT" 2>/dev/null || true
  printf 'astack update: installation failed; previous version restored\n' >&2
  exit 1
fi

sed 's|^SHARE="@SHARE@"$|SHARE="'"$KIT_ROOT"'"|' "$KIT_ROOT/scripts/astack" > "$BIN"
chmod +x "$BIN"
rm -rf "$OLD"
printf 'updated astack to %s\n' "$LATEST"
printf 'run astack upgrade in initialized projects to apply managed-file updates\n'
