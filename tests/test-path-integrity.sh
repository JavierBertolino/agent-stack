#!/usr/bin/env sh
# Path integrity: every repository-relative path an installed role or skill
# names must resolve inside a fresh install, except paths the consuming
# project owns or creates at runtime (spec: shipped-path-integrity).
# Also enforces the shipped-path-integrity scenarios: the run-state helper is
# invoked through the installed CLI, no installed role cites kit-only
# documents, and docs/RUN_STATE.md and the resolver role agree on the
# entry point.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0

report() {
  printf 'FAIL path-integrity: %s\n' "$1" >&2
  FAIL=1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-paths.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
ROOT=$WORK/project
mkdir -p "$ROOT"

# 1. Fixture install so neutral sources and rendered platform files are both
#    checked as they actually ship.
if ! sh "$KIT_ROOT/scripts/setup-agent-stack.sh" init --root "$ROOT" \
  --kit-root "$KIT_ROOT" --platforms opencode,claude,codex,cursor --mcp none \
  >"$WORK/init.log" 2>&1; then
  report 'fixture install failed'
  sed 's/^/  /' "$WORK/init.log" >&2
  exit 1
fi

files=
for f in "$ROOT"/.agent-stack/roles/*.md \
         "$ROOT"/.agent-stack/skills/*/SKILL.md \
         "$ROOT"/.opencode/agents/* \
         "$ROOT"/.claude/agents/* \
         "$ROOT"/.codex/agents/* \
         "$ROOT"/.cursor/agents/*; do
  [ -f "$f" ] && files="$files $f"
done
if [ -z "$files" ]; then
  report 'no installed roles or skills found'
  exit 1
fi

# 2. Collect path candidates: backticked, placeholder-free tokens that contain
#    "/" (directory-qualified paths), plus the project instruction files named
#    without a directory. Bare artifact names (design.md, package.json) are
#    mentions, not paths.
candidates=$WORK/candidates
# shellcheck disable=SC2086  # $files is intentionally word-split
awk -v root="$ROOT/" '
{
  line = $0
  while (match(line, /`[^`]+`/)) {
    tok = substr(line, RSTART + 1, RLENGTH - 2)
    line = substr(line, RSTART + RLENGTH)
    if (tok ~ /[<>]/ || tok ~ /[ ]/ || tok ~ /:\/\//) continue
    if (tok !~ /^[A-Za-z0-9_.][A-Za-z0-9_.\/-]*$/) continue
    keep = (tok ~ /\//)
    if (!keep && (tok == "AGENTS.md" || tok == "CLAUDE.md" \
                  || tok == "UX_AGENTS.md" || tok == "UI_AGENTS.md")) keep = 1
    if (!keep) continue
    src = FILENAME
    if (index(src, root) == 1) src = substr(src, length(root) + 1)
    print src " " tok
  }
}' $files >"$candidates"

# 3. Missing paths must be project-owned or runtime-created.
#    Allowlist (task 4.4): AGENTS.md, CLAUDE.md, UX_AGENTS.md, UI_AGENTS.md,
#    openspec/, reports/, .agent-stack/config.conf, .agent-stack/runs/ — plus
#    the three entries the fixture surfaced: .agent-stack/context/ (bootstrap
#    provenance, produced on demand), .worktrees/ (created when a worktree
#    opens), and .opencode/pipeline-state/ (legacy ledger, deliberately absent).
allowed() {
  case "$1" in
    AGENTS.md|CLAUDE.md|UX_AGENTS.md|UI_AGENTS.md) return 0 ;;
    openspec/*|reports/*) return 0 ;;
    .agent-stack/config.conf) return 0 ;;
    .agent-stack/runs/*|.agent-stack/context/*) return 0 ;;
    .worktrees|.worktrees/*) return 0 ;;
    .opencode/pipeline-state|.opencode/pipeline-state/*) return 0 ;;
    *) return 1 ;;
  esac
}

checked=0
while read -r src path; do
  [ -n "$path" ] || continue
  checked=$((checked + 1))
  [ -e "$ROOT/$path" ] && continue
  allowed "$path" && continue
  report "$src names missing path $path (install root: $ROOT)"
done <"$candidates"

# 4. Installed roles never invoke the kit-side helper or cite kit-only docs.
for f in "$ROOT"/.agent-stack/roles/*.md \
         "$ROOT"/.opencode/agents/* \
         "$ROOT"/.claude/agents/* \
         "$ROOT"/.codex/agents/* \
         "$ROOT"/.cursor/agents/*; do
  [ -f "$f" ] || continue
  rel=${f#"$ROOT"/}
  if grep -q 'scripts/run-state\.py' "$f"; then
    report "$rel invokes scripts/run-state.py; the installed role must document astack run-state"
  fi
  if grep -q 'docs/PRODUCT_INTENT\.md' "$f"; then
    report "$rel references kit-only docs/PRODUCT_INTENT.md"
  fi
done

# 5. docs/RUN_STATE.md and the installed resolver role document the same
#    run-state entry point (spec: "Docs and role disagree").
docs=$KIT_ROOT/docs/RUN_STATE.md
resolver=$ROOT/.opencode/agents/resolver.md
if ! grep -q 'astack run-state' "$docs"; then
  report 'docs/RUN_STATE.md does not name astack run-state as the installed-project entry point'
fi
if ! grep -q 'astack run-state' "$resolver"; then
  report 'installed resolver role does not name astack run-state'
fi
docs_ep=$(grep ' run-state --root' "$docs" | head -1 | awk '{ print $1 }')
role_ep=$(grep ' run-state --root' "$resolver" | head -1 | awk '{ print $1 }')
if [ -z "$docs_ep" ] || [ -z "$role_ep" ] || [ "$docs_ep" != "$role_ep" ]; then
  report "run-state entry point mismatch: docs/RUN_STATE.md '${docs_ep:-<none>}' vs installed resolver '${role_ep:-<none>}'"
fi

# 6. The documented CLI actually runs after init, with --root explicit
#    (spec: "Run-state helper is invoked through the installed CLI").
if PATH="$KIT_ROOT/scripts:$PATH" astack run-state --root "$ROOT" init \
  --run path-test --change path-test >"$WORK/rs.log" 2>&1 \
  && [ -f "$ROOT/.agent-stack/runs/path-test/state.json" ]; then
  printf 'astack run-state ran after init; state landed in .agent-stack/runs/path-test\n'
else
  report 'astack run-state --root <project> init failed after init'
  sed 's/^/  /' "$WORK/rs.log" >&2
  FAIL=1
fi

# 7. No orphan CLI references (spec astack-cli-ops: "Roles point at the skill
#    where they invoke the CLI"). Any installed role or skill that mentions
#    `astack` must also name `astack-ops`; the skill itself counts as
#    installed and names itself in its frontmatter.
for f in $files; do
  [ -f "$f" ] || continue
  grep -q 'astack' "$f" || continue
  rel=${f#"$ROOT"/}
  if grep -q 'astack-ops' "$f"; then
    continue
  fi
  report "$rel mentions astack but never names the astack-ops skill"
done

if [ "$FAIL" -eq 0 ]; then
  printf 'path-integrity: %s installed path candidates resolve; entry points agree\n' \
    "$checked"
fi
[ "$FAIL" -eq 0 ]
