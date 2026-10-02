#!/usr/bin/env sh
# Safe post-merge worktree audit and cleanup tests.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-worktrees.XXXXXX")
trap 'rm -rf "$T"' EXIT INT TERM
FAIL=0

fail() {
  printf 'FAIL %s\n' "$*" >&2
  FAIL=1
}

ROOT=$T/repo
REMOTE=$T/remote.git
BIN=$T/bin
mkdir -p "$ROOT" "$BIN"
git init --bare "$REMOTE" >/dev/null 2>&1
git -C "$ROOT" init -b main >/dev/null 2>&1
git -C "$ROOT" config user.name 'Agent Stack Test'
git -C "$ROOT" config user.email 'agent-stack@example.invalid'
printf 'base\n' > "$ROOT/README.md"
git -C "$ROOT" add README.md
git -C "$ROOT" commit -m base >/dev/null
git -C "$ROOT" remote add origin "$REMOTE"
git -C "$ROOT" push -u origin main >/dev/null 2>&1

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env sh
set -eu
case "${1:-} ${2:-}" in
  'repo view')
    printf '%s\n' 'example/agent-stack-test'
    ;;
  'pr list')
    if [ "${GH_PR_STATE:-}" = MERGED ]; then
      printf '42\tMERGED\t2026-10-02T12:00:00Z\t%s\t%s\tmain\thttps://github.com/example/agent-stack-test/pull/42\n' \
        "$GH_PR_BRANCH" "$GH_PR_HEAD"
    fi
    ;;
  *)
    printf 'unexpected gh invocation: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$BIN/gh"

create_branch() {
  branch=$1
  slug=$(printf '%s' "$branch" | tr '/' '-')
  path=$ROOT/.worktrees/$slug
  mkdir -p "$ROOT/.worktrees"
  git -C "$ROOT" worktree add -b "$branch" "$path" main >/dev/null
  printf '%s\n' "$branch" > "$path/change.txt"
  git -C "$path" add change.txt
  git -C "$path" commit -m "$branch" >/dev/null
  git -C "$path" push -u origin "$branch" >/dev/null 2>&1
  printf '%s\n' "$path"
}

MERGED_BRANCH=feature/merged
MERGED_PATH=$(create_branch "$MERGED_BRANCH")
MERGED_HEAD=$(git -C "$MERGED_PATH" rev-parse HEAD)

audit_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$MERGED_BRANCH" GH_PR_HEAD="$MERGED_HEAD" \
  sh "$KIT_ROOT/scripts/astack" worktree audit --branch "$MERGED_BRANCH") \
  || fail 'dispatcher audit rejected an eligible worktree'
printf '%s\n' "$audit_output" | grep -q "SAFE.*$MERGED_BRANCH" \
  || fail 'audit did not report SAFE'
[ -d "$MERGED_PATH" ] || fail 'audit changed the worktree'

cleanup_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$MERGED_BRANCH" GH_PR_HEAD="$MERGED_HEAD" \
  sh "$KIT_ROOT/scripts/astack" worktree cleanup --branch "$MERGED_BRANCH") \
  || fail 'cleanup rejected an eligible worktree'
printf '%s\n' "$cleanup_output" | grep -q "CLEANED.*$MERGED_BRANCH" \
  || fail 'cleanup did not report CLEANED'
[ ! -e "$MERGED_PATH" ] || fail 'cleanup preserved the eligible worktree'
if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$MERGED_BRANCH"; then
  fail 'cleanup preserved the eligible local branch'
fi
git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$MERGED_BRANCH" >/dev/null 2>&1 \
  || fail 'cleanup deleted the remote branch'

DIRTY_BRANCH=feature/dirty
DIRTY_PATH=$(create_branch "$DIRTY_BRANCH")
DIRTY_HEAD=$(git -C "$DIRTY_PATH" rev-parse HEAD)
printf 'uncommitted\n' > "$DIRTY_PATH/local.txt"
set +e
dirty_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$DIRTY_BRANCH" GH_PR_HEAD="$DIRTY_HEAD" \
  sh "$KIT_ROOT/scripts/astack" worktree cleanup --branch "$DIRTY_BRANCH" 2>&1)
dirty_status=$?
set -e
[ "$dirty_status" -eq 1 ] || fail 'dirty targeted cleanup did not exit 1'
printf '%s\n' "$dirty_output" | grep -q 'working tree is not clean' \
  || fail 'dirty cleanup did not explain the skip'
[ -d "$DIRTY_PATH" ] || fail 'dirty cleanup removed the worktree'

CURRENT_BRANCH=feature/current
CURRENT_PATH=$(create_branch "$CURRENT_BRANCH")
CURRENT_HEAD=$(git -C "$CURRENT_PATH" rev-parse HEAD)
set +e
current_output=$(cd "$CURRENT_PATH" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$CURRENT_BRANCH" GH_PR_HEAD="$CURRENT_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --root "$ROOT" --branch "$CURRENT_BRANCH" 2>&1)
current_status=$?
set -e
[ "$current_status" -eq 1 ] || fail 'current targeted cleanup did not exit 1'
printf '%s\n' "$current_output" | grep -q 'current worktree' \
  || fail 'current cleanup did not explain the skip'
[ -d "$CURRENT_PATH" ] || fail 'current cleanup removed its caller worktree'

OPEN_BRANCH=feature/open
OPEN_PATH=$(create_branch "$OPEN_BRANCH")
OPEN_HEAD=$(git -C "$OPEN_PATH" rev-parse HEAD)
set +e
open_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=OPEN GH_PR_BRANCH="$OPEN_BRANCH" GH_PR_HEAD="$OPEN_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$OPEN_BRANCH" 2>&1)
open_status=$?
set -e
[ "$open_status" -eq 1 ] || fail 'unmerged targeted cleanup did not exit 1'
printf '%s\n' "$open_output" | grep -q 'no merged PR exactly matches' \
  || fail 'unmerged cleanup did not explain the skip'
[ -d "$OPEN_PATH" ] || fail 'unmerged cleanup removed the worktree'

MISMATCH_BRANCH=feature/later-commit
MISMATCH_PATH=$(create_branch "$MISMATCH_BRANCH")
MISMATCH_HEAD=$(git -C "$MISMATCH_PATH" rev-parse HEAD)
printf 'later\n' >> "$MISMATCH_PATH/change.txt"
git -C "$MISMATCH_PATH" add change.txt
git -C "$MISMATCH_PATH" commit -m later >/dev/null
git -C "$MISMATCH_PATH" push >/dev/null 2>&1
set +e
mismatch_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$MISMATCH_BRANCH" GH_PR_HEAD="$MISMATCH_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$MISMATCH_BRANCH" 2>&1)
mismatch_status=$?
set -e
[ "$mismatch_status" -eq 1 ] || fail 'SHA-mismatched targeted cleanup did not exit 1'
printf '%s\n' "$mismatch_output" | grep -q 'no merged PR exactly matches' \
  || fail 'SHA mismatch did not explain the skip'
[ -d "$MISMATCH_PATH" ] || fail 'SHA mismatch cleanup removed the worktree'

[ "$FAIL" -eq 0 ]
