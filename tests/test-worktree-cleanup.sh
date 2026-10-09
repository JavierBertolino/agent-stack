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
git -C "$ROOT" init --separate-git-dir "$T/gitmeta" -b main >/dev/null 2>&1
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
    if [ -n "${GH_HIT_LOG:-}" ]; then
      printf 'hit\n' >> "$GH_HIT_LOG"
    fi
    if [ "${GH_FAIL_PR_QUERY:-}" = 1 ]; then
      printf 'simulated GitHub query failure\n' >&2
      exit 70
    fi
    if [ -n "${GH_SLEEP:-}" ]; then
      sleep "$GH_SLEEP"
    fi
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

create_branch_at() {
  branch=$1
  path=$2
  push_mode=${3:-upstream}
  mkdir -p "$(dirname -- "$path")"
  git -C "$ROOT" worktree add -b "$branch" "$path" main >/dev/null
  printf '%s\n' "$branch" > "$path/change.txt"
  git -C "$path" add change.txt
  git -C "$path" commit -m "$branch" >/dev/null
  if [ "$push_mode" = upstream ]; then
    git -C "$path" push -u origin "$branch" >/dev/null 2>&1
  else
    git -C "$path" push origin "$branch" >/dev/null 2>&1
  fi
  printf '%s\n' "$path"
}

create_branch() {
  branch=$1
  slug=$(printf '%s' "$branch" | tr '/' '-')
  mkdir -p "$ROOT/.worktrees"
  create_branch_at "$branch" "$ROOT/.worktrees/$slug"
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

audit_all_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$MERGED_BRANCH" GH_PR_HEAD="$MERGED_HEAD" \
  sh "$KIT_ROOT/scripts/astack" worktree audit)
printf '%s\n' "$audit_all_output" | grep -q "SAFE.*$MERGED_BRANCH" \
  || fail 'untargeted audit did not find a safe managed worktree'
[ -d "$MERGED_PATH" ] || fail 'untargeted audit changed the worktree'
git -C "$ROOT" show-ref --verify --quiet "refs/heads/$MERGED_BRANCH" \
  || fail 'untargeted audit deleted the local branch'
git -C "$ROOT" ls-remote --exit-code origin "refs/heads/$MERGED_BRANCH" >/dev/null 2>&1 \
  || fail 'untargeted audit deleted the remote branch'

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

IGNORED_BRANCH=feature/ignored
IGNORED_PATH=$(create_branch "$IGNORED_BRANCH")
printf 'secrets.env\n' > "$IGNORED_PATH/.gitignore"
git -C "$IGNORED_PATH" add .gitignore
git -C "$IGNORED_PATH" commit -m 'ignore local secret' >/dev/null
git -C "$IGNORED_PATH" push >/dev/null 2>&1
IGNORED_HEAD=$(git -C "$IGNORED_PATH" rev-parse HEAD)
printf 'keep-me\n' > "$IGNORED_PATH/secrets.env"
set +e
ignored_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$IGNORED_BRANCH" GH_PR_HEAD="$IGNORED_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$IGNORED_BRANCH" 2>&1)
ignored_status=$?
set -e
[ "$ignored_status" -eq 1 ] || fail 'ignored-file cleanup did not exit 1'
printf '%s\n' "$ignored_output" | grep -q 'contains ignored files' \
  || fail 'ignored-file cleanup did not explain the skip'
[ "$(cat "$IGNORED_PATH/secrets.env")" = keep-me ] \
  || fail 'ignored-file cleanup deleted user data'
[ -d "$IGNORED_PATH" ] || fail 'ignored-file cleanup removed the worktree'

OUTSIDE_BRANCH=feature/outside
OUTSIDE_PATH=$(create_branch_at "$OUTSIDE_BRANCH" "$T/outside-worktree")
OUTSIDE_HEAD=$(git -C "$OUTSIDE_PATH" rev-parse HEAD)
set +e
outside_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$OUTSIDE_BRANCH" GH_PR_HEAD="$OUTSIDE_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --root "$ROOT" --branch "$OUTSIDE_BRANCH" 2>&1)
outside_status=$?
set -e
[ "$outside_status" -eq 1 ] || fail 'outside targeted cleanup did not exit 1'
printf '%s\n' "$outside_output" | grep -q 'not inside the managed .worktrees directory' \
  || fail 'outside cleanup did not explain the containment refusal'
[ -d "$OUTSIDE_PATH" ] || fail 'outside cleanup removed the worktree'

NESTED_BRANCH=feature/nested
NESTED_PATH=$(create_branch_at "$NESTED_BRANCH" "$ROOT/.worktrees/nested/child")
NESTED_HEAD=$(git -C "$NESTED_PATH" rev-parse HEAD)
set +e
nested_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$NESTED_BRANCH" GH_PR_HEAD="$NESTED_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$NESTED_BRANCH" 2>&1)
nested_status=$?
set -e
[ "$nested_status" -eq 1 ] || fail 'nested targeted cleanup did not exit 1'
printf '%s\n' "$nested_output" | grep -q 'not directly below the managed .worktrees directory' \
  || fail 'nested cleanup did not explain the containment refusal'
[ -d "$NESTED_PATH" ] || fail 'nested cleanup removed the worktree'

LOCKED_BRANCH=feature/locked
LOCKED_PATH=$(create_branch "$LOCKED_BRANCH")
LOCKED_HEAD=$(git -C "$LOCKED_PATH" rev-parse HEAD)
git -C "$ROOT" worktree lock --reason 'test retention' "$LOCKED_PATH"
set +e
locked_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$LOCKED_BRANCH" GH_PR_HEAD="$LOCKED_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$LOCKED_BRANCH" 2>&1)
locked_status=$?
set -e
[ "$locked_status" -eq 1 ] || fail 'locked targeted cleanup did not exit 1'
printf '%s\n' "$locked_output" | grep -q 'locked worktree: test retention' \
  || fail 'locked cleanup did not explain the lock reason'
[ -d "$LOCKED_PATH" ] || fail 'locked cleanup removed the worktree'
git -C "$ROOT" worktree unlock "$LOCKED_PATH"

NO_UPSTREAM_BRANCH=feature/no-upstream
NO_UPSTREAM_PATH=$(create_branch_at "$NO_UPSTREAM_BRANCH" "$ROOT/.worktrees/no-upstream" no-upstream)
NO_UPSTREAM_HEAD=$(git -C "$NO_UPSTREAM_PATH" rev-parse HEAD)
if git -C "$ROOT" config --get "branch.$NO_UPSTREAM_BRANCH.remote" >/dev/null 2>&1; then
  fail 'no-upstream fixture unexpectedly has a configured tracking remote'
fi
DIVERGENCE_CLONE=$T/divergence-clone
git clone "$REMOTE" "$DIVERGENCE_CLONE" >/dev/null 2>&1
git -C "$DIVERGENCE_CLONE" config user.name 'Agent Stack Test'
git -C "$DIVERGENCE_CLONE" config user.email 'agent-stack@example.invalid'
git -C "$DIVERGENCE_CLONE" checkout -b "$NO_UPSTREAM_BRANCH" "origin/$NO_UPSTREAM_BRANCH" >/dev/null 2>&1
printf 'remote-only\n' >> "$DIVERGENCE_CLONE/change.txt"
git -C "$DIVERGENCE_CLONE" add change.txt
git -C "$DIVERGENCE_CLONE" commit -m 'advance remote branch' >/dev/null
git -C "$DIVERGENCE_CLONE" push origin "$NO_UPSTREAM_BRANCH" >/dev/null 2>&1
set +e
remote_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$NO_UPSTREAM_BRANCH" GH_PR_HEAD="$NO_UPSTREAM_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$NO_UPSTREAM_BRANCH" 2>&1)
remote_status=$?
set -e
[ "$remote_status" -eq 1 ] || fail 'diverged remote targeted cleanup did not exit 1'
printf '%s\n' "$remote_output" | grep -q 'remote branch contains a different HEAD' \
  || fail 'diverged remote cleanup did not enforce the origin fallback'
[ -d "$NO_UPSTREAM_PATH" ] || fail 'diverged remote cleanup removed the worktree'

REMOTE_ERROR_BRANCH=feature/remote-query-error
REMOTE_ERROR_PATH=$(create_branch "$REMOTE_ERROR_BRANCH")
REMOTE_ERROR_HEAD=$(git -C "$REMOTE_ERROR_PATH" rev-parse HEAD)
git -C "$ROOT" config "branch.$REMOTE_ERROR_BRANCH.pushRemote" missing-remote
set +e
remote_error_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH="$REMOTE_ERROR_BRANCH" GH_PR_HEAD="$REMOTE_ERROR_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$REMOTE_ERROR_BRANCH" 2>&1)
remote_error_status=$?
set -e
[ "$remote_error_status" -eq 2 ] || fail 'remote query failure did not produce a tool-error status'
printf '%s\n' "$remote_error_output" | grep -q 'cannot query remote branch from missing-remote' \
  || fail 'remote query failure was not reported'
[ -d "$REMOTE_ERROR_PATH" ] || fail 'remote query failure removed the worktree'
git -C "$ROOT" config --unset "branch.$REMOTE_ERROR_BRANCH.pushRemote"

PR_ERROR_BRANCH=feature/pr-query-error
PR_ERROR_PATH=$(create_branch "$PR_ERROR_BRANCH")
PR_ERROR_HEAD=$(git -C "$PR_ERROR_PATH" rev-parse HEAD)
set +e
pr_error_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  GH_FAIL_PR_QUERY=1 GH_PR_STATE=MERGED GH_PR_BRANCH="$PR_ERROR_BRANCH" GH_PR_HEAD="$PR_ERROR_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch "$PR_ERROR_BRANCH" 2>&1)
pr_error_status=$?
set -e
[ "$pr_error_status" -eq 2 ] || fail 'GitHub query failure did not produce a tool-error status'
printf '%s\n' "$pr_error_output" | grep -q 'cannot query GitHub pull requests' \
  || fail 'GitHub query failure was not reported'
[ -d "$PR_ERROR_PATH" ] || fail 'GitHub query failure removed the worktree'

REAL_GIT=$(command -v git)
FAIL_GIT_BIN=$T/fail-git-bin
mkdir -p "$FAIL_GIT_BIN"
cat > "$FAIL_GIT_BIN/git" <<EOF
#!/usr/bin/env sh
case "\$*" in
  *' worktree prune') exit 71 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$FAIL_GIT_BIN/git"
set +e
prune_output=$(cd "$ROOT" && PATH="$FAIL_GIT_BIN:$BIN:$PATH" \
  GH_PR_STATE=MERGED GH_PR_BRANCH=feature/dirty GH_PR_HEAD="$DIRTY_HEAD" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" cleanup --branch feature/dirty 2>&1)
prune_status=$?
set -e
[ "$prune_status" -eq 2 ] || fail 'prune failure did not produce a tool-error status'
printf '%s\n' "$prune_output" | grep -q 'ERROR.*worktree prune failed' \
  || fail 'prune failure was not reported'
printf '%s\n' "$prune_output" | grep -q 'SUMMARY.*errors=1' \
  || fail 'prune failure prevented the cleanup summary'
[ -d "$DIRTY_PATH" ] || fail 'prune failure removed an ineligible worktree'

DETACHED_PATH=$ROOT/.worktrees/detached
git -C "$ROOT" worktree add --detach "$DETACHED_PATH" main >/dev/null
set +e
detached_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" audit 2>&1)
detached_status=$?
set -e
[ "$detached_status" -eq 0 ] || fail 'audit rejected an unrelated detached worktree'
printf '%s\n' "$detached_output" | grep -q '(detached).*detached HEAD' \
  || fail 'audit did not report the detached worktree reason'
set +e
missing_output=$(cd "$ROOT" && PATH="$BIN:$PATH" \
  sh "$KIT_ROOT/scripts/worktree-cleanup.sh" audit --branch feature/not-present 2>&1)
missing_status=$?
set -e
[ "$missing_status" -eq 1 ] || fail 'missing targeted branch did not exit 1'
printf '%s\n' "$missing_output" | grep -q 'no attached worktree matches the requested branch' \
  || fail 'missing branch did not explain why no worktree matched'

INT_BRANCH=feature/interrupt
INT_PATH=$(create_branch "$INT_BRANCH")
INT_HIT_LOG=$T/interrupt-hit.log
INT_OUTPUT=$T/interrupt-output.log
if PATH="$BIN:$PATH" GH_PR_STATE=MERGED GH_PR_BRANCH="$INT_BRANCH" \
    GH_PR_HEAD="$(git -C "$INT_PATH" rev-parse HEAD)" GH_SLEEP=2 GH_HIT_LOG="$INT_HIT_LOG" \
    node - "$KIT_ROOT/scripts/worktree-cleanup.sh" "$ROOT" "$INT_BRANCH" "$INT_HIT_LOG" "$INT_OUTPUT" <<'NODE'
const { spawn } = require('node:child_process');
const fs = require('node:fs');

const [script, root, branch, hitLog, output] = process.argv.slice(2);
const stdout = fs.openSync(output, 'w');
const stderr = fs.openSync(output, 'a');
const child = spawn('sh', [script, 'cleanup', '--root', root, '--branch', branch], {
  detached: true,
  env: process.env,
  stdio: ['ignore', stdout, stderr],
});
let sentInterrupt = false;
const poll = setInterval(() => {
  if (fs.existsSync(hitLog)) {
    sentInterrupt = true;
    clearInterval(poll);
    try {
      process.kill(-child.pid, 'SIGINT');
    } catch (error) {
      console.error(`could not interrupt cleanup process group: ${error.message}`);
      process.exitCode = 1;
    }
  }
}, 50);
const timeout = setTimeout(() => {
  console.error('interrupt test never reached the slow GitHub query');
  try {
    process.kill(-child.pid, 'SIGKILL');
  } catch {}
}, 5000);

child.once('error', (error) => {
  console.error(`could not start cleanup: ${error.message}`);
  process.exitCode = 1;
});
child.once('close', (code, signal) => {
  clearInterval(poll);
  clearTimeout(timeout);
  fs.closeSync(stdout);
  fs.closeSync(stderr);
  if (!sentInterrupt) {
    console.error('interrupt test never signalled cleanup');
    process.exitCode = 1;
  } else if (code !== 130 && signal !== 'SIGINT') {
    console.error(`expected cleanup to stop on SIGINT; got code=${code}, signal=${signal}`);
    process.exitCode = 1;
  }
});
NODE
then
  :
else
  fail 'Ctrl-C did not abort cleanup with status 130'
  cat "$INT_OUTPUT" >&2
fi
[ -d "$INT_PATH" ] || fail 'Ctrl-C allowed cleanup to remove the worktree'
if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$INT_BRANCH"; then
  :
else
  fail 'Ctrl-C allowed cleanup to delete the local branch'
fi

[ "$FAIL" -eq 0 ]
