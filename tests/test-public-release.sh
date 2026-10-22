#!/usr/bin/env sh
# Public-release tests: versioned install from a release artifact, checksum
# verification, `astack update` / `update --check`, `astack upgrade`
# version tracking, and the init Jev hint.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-public.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

VERSION=$(awk 'NR == 1 { print $1; exit }' "$KIT_ROOT/VERSION")
# The fake "newer release" below must stay above the kit version, or the
# update checks compare a release against itself and pass vacuously.
NEXT=$(printf '%s\n' "$VERSION" | awk -F. '{ printf "%s.%s.%d\n", $1, $2, $3 + 1 }')
[ "$NEXT" != "$VERSION" ] || { printf 'FAIL NEXT version equals VERSION\n' >&2; exit 1; }
DIST=$WORK/dist
P=$WORK/prefix
T=$WORK/project
mkdir -p "$T"

# Build the release artifacts (skip the inner smoke test; this file is the smoke test).
python3 "$KIT_ROOT/scripts/build-release.sh" --kit-root "$KIT_ROOT" --dist "$DIST" --skip-smoke >/dev/null 2>&1 \
  || { printf 'FAIL build-release\n' >&2; FAIL=1; }
for artifact in astack.tar.gz astack.tar.gz.sha256 checksums.txt install.sh VERSION; do
  [ -f "$DIST/$artifact" ] || { printf 'FAIL release artifact missing: %s\n' "$artifact" >&2; FAIL=1; }
done
tar -tzf "$DIST/astack.tar.gz" | grep -qx 'cli/dist/bin.js' \
  || { printf 'FAIL release archive is missing cli/dist/bin.js\n' >&2; FAIL=1; }

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    printf 'no sha256 tool\n' >&2
    return 1
  fi
}

# Portable checksum: 64 hex digits, two spaces, then the file name.
# Both sha256sum -c and shasum -a 256 -c accept that line.
sha256_check() {
  sumfile=$1
  line=$(awk 'NR == 1 { print; exit }' "$sumfile")
  printf '%s\n' "$line" | grep -E '^[0-9a-f]{64}  [^ *].+$' >/dev/null \
    || { printf 'FAIL checksum line is not the portable two-space form: %s\n' "$line" >&2; return 1; }
  want=$(printf '%s\n' "$line" | awk '{ print $1 }')
  name=$(printf '%s\n' "$line" | awk '{ print $2 }')
  got=$(sha256_hex "$name") || return 1
  [ "$got" = "$want" ] || { printf 'FAIL checksum mismatch for %s\n' "$name" >&2; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$sumfile" >/dev/null 2>&1
  else
    shasum -a 256 -c "$sumfile" >/dev/null 2>&1
  fi
}

(cd "$DIST" && sha256_check astack.tar.gz.sha256) \
  || { printf 'FAIL release checksum invalid\n' >&2; FAIL=1; }

# macOS ships shasum and not sha256sum. The same file must verify there.
SHA_ONLY=$WORK/sha-only
mkdir -p "$SHA_ONLY"
for tool in shasum awk grep; do
  src=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$src" ] || continue
  ln -sf "$src" "$SHA_ONLY/$tool"
done
if [ -x "$SHA_ONLY/shasum" ]; then
  (cd "$DIST" && PATH="$SHA_ONLY" sha256_check astack.tar.gz.sha256) \
    || { printf 'FAIL release checksum invalid without sha256sum\n' >&2; FAIL=1; }
fi

# Public install from the release artifact (no checkout needed at install time).
ASTACK_RELEASE_BASE=$DIST sh "$KIT_ROOT/install.sh" --prefix="$P" >"$WORK/install.log" 2>&1 \
  || { printf 'FAIL public install\n' >&2; FAIL=1; }
grep -q "Agent Stack v$VERSION installed successfully" "$WORK/install.log" \
  || { printf 'FAIL install success message\n' >&2; FAIL=1; }
grep -q 'astack init' "$WORK/install.log" \
  || { printf 'FAIL install next-steps mention astack init\n' >&2; FAIL=1; }
grep -q 'astack doctor' "$WORK/install.log" \
  || { printf 'FAIL install next-steps mention astack doctor\n' >&2; FAIL=1; }
[ "$("$P/bin/astack" --version)" = "$VERSION" ] \
  || { printf 'FAIL installed version mismatch\n' >&2; FAIL=1; }

# Corrupted checksum must abort the install.
BAD=$WORK/badbase
mkdir -p "$BAD"
cp "$DIST/astack.tar.gz" "$DIST/VERSION" "$BAD/" 2>/dev/null || cp "$KIT_ROOT/VERSION" "$BAD/VERSION"
printf 'deadbeef  astack.tar.gz\n' > "$BAD/astack.tar.gz.sha256"
if ASTACK_RELEASE_BASE=$BAD sh "$KIT_ROOT/install.sh" --prefix="$WORK/badprefix" >/dev/null 2>&1; then
  printf 'FAIL corrupt checksum must abort install\n' >&2; FAIL=1
fi

# macOS shasum -c exits 0 for a short digest. A sha256sum that does the same
# for -c must still abort.
STUB=$WORK/sha-stub
mkdir -p "$STUB"
cat > "$STUB/sha256sum" <<'EOF'
#!/bin/sh
if [ "$1" = "-c" ]; then
  exit 0
fi
if [ -x /usr/bin/sha256sum ]; then
  exec /usr/bin/sha256sum "$@"
fi
exec shasum -a 256 "$@"
EOF
chmod +x "$STUB/sha256sum"
if PATH="$STUB:$PATH" ASTACK_RELEASE_BASE=$BAD sh "$KIT_ROOT/install.sh" --prefix="$WORK/badprefix-stub" >/dev/null 2>&1; then
  printf 'FAIL corrupt checksum must abort when sha256sum -c is a no-op\n' >&2
  FAIL=1
fi

# Init records the kit version and points at `astack auth jev` when Jev is
# absent. Force that state: hermetic XDG_CONFIG_HOME and no key variables, so
# the check passes on machines where the developer has configured Jev.
(
  unset TYPESAFE_API_KEY AI_GATEWAY_API_KEY JEV_GATEWAY_API_KEY
  cd "$T" || exit 1
  XDG_CONFIG_HOME="$WORK/xdg" PATH="$P/bin:$PATH" \
    astack init --platforms opencode --mcp none >"$WORK/init.log" 2>&1
) || { printf 'FAIL init\n' >&2; FAIL=1; }
grep -q 'Jev is not configured yet' "$WORK/init.log" \
  || { printf 'FAIL init must print the Jev follow-up\n' >&2; FAIL=1; }
grep -q 'astack auth jev' "$WORK/init.log" \
  || { printf 'FAIL init must mention astack auth jev\n' >&2; FAIL=1; }

# update --check reports current when versions match.
export ASTACK_HOME=$P/share/astack ASTACK_RELEASE_BASE=$DIST
(cd "$T" && PATH="$P/bin:$PATH" astack update --check >"$WORK/check.log" 2>&1) \
  || { printf 'FAIL update --check\n' >&2; FAIL=1; }
grep -q "Agent Stack $VERSION is current" "$WORK/check.log" \
  || { printf 'FAIL update --check must report current\n' >&2; FAIL=1; }

# Fake a newer release and update to it.
NEWDIST=$WORK/newdist
mkdir -p "$NEWDIST"
printf '%s\n' "$NEXT" > "$WORK/newversion"
NEWTREE=$WORK/newtree
mkdir -p "$NEWTREE"
cp -r "$KIT_ROOT/scripts" "$KIT_ROOT/.agent-stack" "$NEWTREE/"
printf '%s\n' "$NEXT" > "$NEWTREE/VERSION"
tar -czf "$NEWDIST/astack.tar.gz" -C "$NEWTREE" scripts .agent-stack VERSION
(cd "$NEWDIST" && printf '%s  astack.tar.gz\n' "$(sha256_hex astack.tar.gz)" > astack.tar.gz.sha256)
printf '%s\n' "$NEXT" > "$NEWDIST/VERSION"
ASTACK_RELEASE_BASE=$NEWDIST PATH="$P/bin:$PATH" sh "$P/share/astack/current/scripts/update-agent-stack.sh" --check >"$WORK/check2.log" 2>&1 \
  || { printf 'FAIL update --check with newer release\n' >&2; FAIL=1; }
grep -q "Agent Stack $NEXT is available" "$WORK/check2.log" \
  || { printf 'FAIL update --check must report \$NEXT available\n' >&2; FAIL=1; }
grep -q "Current version: $VERSION" "$WORK/check2.log" \
  || { printf 'FAIL update --check must print the current version\n' >&2; FAIL=1; }
ASTACK_RELEASE_BASE=$NEWDIST PATH="$P/bin:$PATH" sh "$P/share/astack/current/scripts/update-agent-stack.sh" >"$WORK/update.log" 2>&1 \
  || { printf 'FAIL update to \$NEXT\n' >&2; FAIL=1; }
grep -q "Agent Stack updated to $NEXT" "$WORK/update.log" \
  || { printf 'FAIL update success message\n' >&2; FAIL=1; }
[ "$("$P/bin/astack" --version)" = "$NEXT" ] \
  || { printf 'FAIL version after update\n' >&2; FAIL=1; }
[ -d "$P/share/astack/versions/$VERSION" ] \
  || { printf 'FAIL previous version must be retained for rollback\n' >&2; FAIL=1; }
[ "$(readlink "$P/share/astack/current")" = "versions/$NEXT" ] \
  || { printf 'FAIL current symlink must point at \$NEXT\n' >&2; FAIL=1; }

# The project still records the old version; upgrade migrates it.
[ "$(cat "$T/.agent-stack/.kit-version")" = "$VERSION" ] \
  || { printf 'FAIL project keeps its init version until upgrade\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" astack upgrade >"$WORK/upgrade.log" 2>&1) \
  || { printf 'FAIL astack upgrade\n' >&2; FAIL=1; }
grep -q "$VERSION → $NEXT" "$WORK/upgrade.log" \
  || { printf 'FAIL upgrade must show old → new\n' >&2; FAIL=1; }
grep -q 'Project upgraded successfully' "$WORK/upgrade.log" \
  || { printf 'FAIL upgrade success message\n' >&2; FAIL=1; }
[ "$(cat "$T/.agent-stack/.kit-version")" = "$NEXT" ] \
  || { printf 'FAIL .kit-version must advance on upgrade\n' >&2; FAIL=1; }

unset ASTACK_HOME ASTACK_RELEASE_BASE
[ "$FAIL" -eq 0 ]
