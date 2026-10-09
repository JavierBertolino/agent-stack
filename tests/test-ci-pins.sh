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

# 1. No floating tags: global npm installs must name an exact x.y.z, and
#    registry shortcuts (latest/next/beta/canary) are forbidden in workflows.
unpinned=$(grep -RhE 'npm[[:space:]]+(i|install)([[:space:]].*)?(-g|--global)' \
  "$WF"/*.y*ml 2>/dev/null \
  | grep -vE '@[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)' || true)
if [ -n "$unpinned" ]; then
  printf 'FAIL unpinned global npm install (declare the exact version in package.json):\n%s\n' \
    "$unpinned" >&2
  FAIL=1
fi
floating=$(grep -RhE '@(latest|next|beta|canary)([^[:alnum:]._-]|$)' \
  "$WF"/*.y*ml 2>/dev/null || true)
if [ -n "$floating" ]; then
  printf 'FAIL floating npm dist-tag in workflows:\n%s\n' "$floating" >&2
  FAIL=1
fi

# 2. External actions are SHA-pinned; local reusable workflows use a path.
unsha=$(grep -RhE '^[[:space:]]*uses:' "$WF"/*.y*ml 2>/dev/null \
  | grep -vE 'uses:[[:space:]]+\./' \
  | grep -vE 'uses:[[:space:]]+[^[:space:]]+@[0-9a-fA-F]{40}([[:space:]]+#.*)?$' || true)
if [ -n "$unsha" ]; then
  printf 'FAIL workflow action is not SHA-pinned:\n%s\n' \
    "$unsha" >&2
  FAIL=1
fi

# 3. The manifest, lockfile root dependency, and installed package all agree
#    on one exact version.
if ! node -e '
  const fs = require("node:fs");
  const [manifestPath, lockPath] = process.argv.slice(1);
  const name = "@fission-ai/openspec";
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
  const version = manifest.dependencies?.[name];
  const rootVersion = lock.packages?.[""]?.dependencies?.[name];
  const packageVersion = lock.packages?.[`node_modules/${name}`]?.version;
  if (!/^\d+\.\d+\.\d+$/.test(version || "") ||
      rootVersion !== version || packageVersion !== version) {
    console.error(`manifest=${version}; lock root=${rootVersion}; lock package=${packageVersion}`);
    process.exit(1);
  }
' "$KIT_ROOT/package.json" "$KIT_ROOT/package-lock.json"; then
  report 'package.json and package-lock.json must agree on one exact OpenSpec version'
fi

# 4. CI installs the lockfile pin, while release falls back for historical
#    tags that do not contain package-lock.json.
PIN=$(node -p 'require(process.argv[1]).dependencies["@fission-ai/openspec"]' \
  "$KIT_ROOT/package.json")
for f in "$WF/ci.yml" "$WF/release.yml"; do
  if [ ! -f "$f" ]; then
    report "missing workflow $f"
  elif ! grep -qE '^[[:space:]]*npm ci([[:space:]]|$)' "$f"; then
    report "$(basename "$f") does not run npm ci as a workflow command"
  fi
done
if ! grep -qF 'npm install --global @fission-ai/openspec@'"$PIN" "$WF/release.yml"; then
  report 'release.yml needs the exact-pin fallback for historical lockfile-free tags'
fi

# 5. dependabot covers the directory that holds package.json.
npm_dir=$(awk '/- package-ecosystem:/ { flag = ($0 ~ /npm$/) }
  flag && /^[[:space:]]*directory:/ { print $2; flag = 0 }' "$DEP" 2>/dev/null || true)
if [ "$npm_dir" != "/" ]; then
  report "dependabot.yml needs an npm entry with directory: / (got '${npm_dir:-<none>}')"
fi

# 6. The standalone installer is intentionally hidden from GitHub's generated
#    diff, but must remain classified so CI can verify the generated artifact.
if ! grep -Fxq 'setup.sh linguist-generated' "$KIT_ROOT/.gitattributes"; then
  report '.gitattributes must mark setup.sh as linguist-generated'
fi

[ "$FAIL" -eq 0 ]
