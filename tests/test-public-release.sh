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
(cd "$DIST" && sha256sum -c astack.tar.gz.sha256 >/dev/null 2>&1) \
  || { printf 'FAIL release checksum invalid\n' >&2; FAIL=1; }

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

# Init records the kit version and points at `astack auth jev` when Jev is absent.
(cd "$T" && PATH="$P/bin:$PATH" astack init --platforms opencode --mcp none >"$WORK/init.log" 2>&1) \
  || { printf 'FAIL init\n' >&2; FAIL=1; }
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
printf '0.2.0\n' > "$WORK/newversion"
NEWTREE=$WORK/newtree
mkdir -p "$NEWTREE"
cp -r "$KIT_ROOT/scripts" "$KIT_ROOT/.agent-stack" "$NEWTREE/"
printf '0.2.0\n' > "$NEWTREE/VERSION"
tar -czf "$NEWDIST/astack.tar.gz" -C "$NEWTREE" scripts .agent-stack VERSION
(cd "$NEWDIST" && sha256sum astack.tar.gz | awk '{ print $1 "  astack.tar.gz" }' > astack.tar.gz.sha256)
printf '0.2.0\n' > "$NEWDIST/VERSION"
ASTACK_RELEASE_BASE=$NEWDIST PATH="$P/bin:$PATH" sh "$P/share/astack/current/scripts/update-agent-stack.sh" --check >"$WORK/check2.log" 2>&1 \
  || { printf 'FAIL update --check with newer release\n' >&2; FAIL=1; }
grep -q 'Agent Stack 0.2.0 is available' "$WORK/check2.log" \
  || { printf 'FAIL update --check must report 0.2.0 available\n' >&2; FAIL=1; }
grep -q "Current version: $VERSION" "$WORK/check2.log" \
  || { printf 'FAIL update --check must print the current version\n' >&2; FAIL=1; }
ASTACK_RELEASE_BASE=$NEWDIST PATH="$P/bin:$PATH" sh "$P/share/astack/current/scripts/update-agent-stack.sh" >"$WORK/update.log" 2>&1 \
  || { printf 'FAIL update to 0.2.0\n' >&2; FAIL=1; }
grep -q 'Agent Stack updated to 0.2.0' "$WORK/update.log" \
  || { printf 'FAIL update success message\n' >&2; FAIL=1; }
[ "$("$P/bin/astack" --version)" = "0.2.0" ] \
  || { printf 'FAIL version after update\n' >&2; FAIL=1; }
[ -d "$P/share/astack/versions/$VERSION" ] \
  || { printf 'FAIL previous version must be retained for rollback\n' >&2; FAIL=1; }
[ "$(readlink "$P/share/astack/current")" = "versions/0.2.0" ] \
  || { printf 'FAIL current symlink must point at 0.2.0\n' >&2; FAIL=1; }

# The project still records the old version; upgrade migrates it.
[ "$(cat "$T/.agent-stack/.kit-version")" = "$VERSION" ] \
  || { printf 'FAIL project keeps its init version until upgrade\n' >&2; FAIL=1; }
(cd "$T" && PATH="$P/bin:$PATH" astack upgrade >"$WORK/upgrade.log" 2>&1) \
  || { printf 'FAIL astack upgrade\n' >&2; FAIL=1; }
grep -q "$VERSION → 0.2.0" "$WORK/upgrade.log" \
  || { printf 'FAIL upgrade must show old → new\n' >&2; FAIL=1; }
grep -q 'Project upgraded successfully' "$WORK/upgrade.log" \
  || { printf 'FAIL upgrade success message\n' >&2; FAIL=1; }
[ "$(cat "$T/.agent-stack/.kit-version")" = "0.2.0" ] \
  || { printf 'FAIL .kit-version must advance on upgrade\n' >&2; FAIL=1; }

unset ASTACK_HOME ASTACK_RELEASE_BASE
[ "$FAIL" -eq 0 ]
