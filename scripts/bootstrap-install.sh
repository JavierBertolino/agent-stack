#!/usr/bin/env sh
# Public installer for Agent Stack releases.
set -eu

REPOSITORY=${ASTACK_REPOSITORY:-JavierBertolino/agent-stack}
PREFIX=${ASTACK_PREFIX:-$HOME/.local}
VERSION=${ASTACK_VERSION:-latest}

command -v curl >/dev/null 2>&1 || { echo "astack installer: curl is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "astack installer: tar is required" >&2; exit 1; }

if [ "$VERSION" = latest ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPOSITORY/releases/latest" | awk -F'"' '/"tag_name"[[:space:]]*:/ { print $4; exit }')
else
  case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
fi
[ -n "$VERSION" ] || { echo "astack installer: could not resolve a release" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/astack-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BASE="https://github.com/$REPOSITORY/releases/download/$VERSION"
curl -fsSL "$BASE/astack.tar.gz" -o "$TMP/astack.tar.gz"
curl -fsSL "$BASE/astack.tar.gz.sha256" -o "$TMP/astack.tar.gz.sha256"

EXPECTED=$(awk '{print $1}' "$TMP/astack.tar.gz.sha256")
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL=$(sha256sum "$TMP/astack.tar.gz" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL=$(shasum -a 256 "$TMP/astack.tar.gz" | awk '{print $1}')
else
  echo "astack installer: sha256sum or shasum is required" >&2
  exit 1
fi
[ "$EXPECTED" = "$ACTUAL" ] || { echo "astack installer: checksum verification failed" >&2; exit 1; }

SHARE="$PREFIX/share/astack"
mkdir -p "$PREFIX/bin" "$PREFIX/share"
rm -rf "$TMP/new"
mkdir -p "$TMP/new"
tar -xzf "$TMP/astack.tar.gz" -C "$TMP/new"
[ -f "$TMP/new/scripts/astack" ] || { echo "astack installer: invalid release archive" >&2; exit 1; }
rm -rf "$SHARE"
mv "$TMP/new" "$SHARE"
sed 's|^SHARE="@SHARE@"$|SHARE="'"$SHARE"'"|' "$SHARE/scripts/astack" > "$PREFIX/bin/astack"
chmod +x "$PREFIX/bin/astack"

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *)
    echo "Add astack to PATH:"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
    ;;
esac

echo "Installed $("$PREFIX/bin/astack" --version)"
echo "Next: cd into a project and run: astack init"
