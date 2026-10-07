#!/usr/bin/env sh
# CI pin hygiene: third-party tooling and actions are pinned to exact
# versions, and the tooling pin is declared where dependabot can bump it.
# Covers the ci-dependency-pinning scenarios "Audit of workflow pins" and
# "The pin exists everywhere it is used".
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
WF=$KIT_ROOT/.github/workflows
DEP=$KIT_ROOT/.github/dependabot.yml
FAIL=0

report() {
  printf 'FAIL %s\n' "$1" >&2
  FAIL=1
}

# 1. No floating tags: any npm install -g must name an exact x.y.z, and no
#    workflow may reference @latest at all.
unpinned=$(grep -Rn "npm install -g" "$WF" 2>/dev/null \
  | grep -vE "@[0-9]+\.[0-9]+\.[0-9]+" || true)
if [ -n "$unpinned" ]; then
  printf 'FAIL unpinned npm install (declare the exact version in package.json):\n%s\n' \
    "$unpinned" >&2
  FAIL=1
fi
latest=$(grep -Rn "@latest" "$WF" 2>/dev/null || true)
if [ -n "$latest" ]; then
  printf 'FAIL floating @latest reference in workflows:\n%s\n' "$latest" >&2
  FAIL=1
fi

# 2. Every uses: is SHA-pinned with a trailing version comment.
unsha=$(grep -Rh "uses:" "$WF"/*.yml 2>/dev/null \
  | grep -vE "@[0-9a-f]{40}[[:space:]]+#" || true)
if [ -n "$unsha" ]; then
  printf 'FAIL workflow action not SHA-pinned with a version comment:\n%s\n' \
    "$unsha" >&2
  FAIL=1
fi

# 3. The tooling pin is an exact version in package.json.
if ! grep -qE '"@fission-ai/openspec":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' \
  "$KIT_ROOT/package.json"; then
  report 'package.json must pin @fission-ai/openspec to an exact x.y.z version'
fi

# 4. Both workflows consume that pin through npm ci.
for f in "$WF/ci.yml" "$WF/release.yml"; do
  if [ ! -f "$f" ]; then
    report "missing workflow $f"
  elif ! grep -q "npm ci" "$f"; then
    report "$(basename "$f") does not install the pinned tooling via npm ci"
  fi
done

# 5. dependabot covers the directory that holds package.json.
npm_dir=$(awk '/- package-ecosystem:/ { flag = ($0 ~ /npm$/) }
  flag && /^[[:space:]]*directory:/ { print $2; flag = 0 }' "$DEP" 2>/dev/null || true)
if [ "$npm_dir" != "/" ]; then
  report "dependabot.yml needs an npm entry with directory: / (got '${npm_dir:-<none>}')"
fi

[ "$FAIL" -eq 0 ]
