#!/usr/bin/env sh
# Audit or remove Agent Stack-managed worktrees after their PRs are merged.
set -eu

MODE=audit
ROOT=$PWD
BRANCH_FILTER=

usage() {
  cat <<'EOF'
Usage:
  astack worktree audit [--root PATH] [--branch BRANCH]
  astack worktree cleanup [--root PATH] [--branch BRANCH]

audit reports worktrees that are safe to remove without changing anything.
cleanup removes the worktree and its local branch only when all safety checks
pass. Remote branches are never deleted.

Safety checks require the worktree to:
  - live directly below the repository's .worktrees/ directory;
  - not be the caller's current worktree;
  - have a local branch and a clean working tree;
  - have a GitHub PR whose state is MERGED;
  - exactly match that merged PR's head SHA;
  - match the remote branch SHA when the remote branch still exists.

With --branch, a skipped or missing branch exits 1 so closeout automation can
stop safely. Without --branch, unsafe and active worktrees are reported and
left untouched while the command exits successfully unless a tool fails.
EOF
}

die() {
  printf '%s\n' "worktree-cleanup: $*" >&2
  exit 2
}

canonical_dir() {
  CDPATH= cd -- "$1" 2>/dev/null && pwd -P
}

case "${1:-}" in
  audit|cleanup) MODE=$1; shift ;;
  ''|-h|--help) usage; exit 0 ;;
  *) die "unknown action: $1 (expected audit or cleanup)" ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*) ROOT=${1#--root=}; shift ;;
    --root)
      [ "$#" -gt 1 ] || die '--root requires a path'
      ROOT=$2
      shift 2
      ;;
    --branch=*) BRANCH_FILTER=${1#--branch=}; shift ;;
    --branch)
      [ "$#" -gt 1 ] || die '--branch requires a branch name'
      BRANCH_FILTER=$2
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die 'git is required'
command -v gh >/dev/null 2>&1 || die 'GitHub CLI (gh) is required'
[ -d "$ROOT" ] || die "root does not exist: $ROOT"

target_top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) \
  || die "not a Git repository: $ROOT"
common_dir=$(git -C "$target_top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "cannot resolve common Git directory: $target_top"
repo_root=$(canonical_dir "$(dirname -- "$common_dir")") \
  || die "cannot resolve primary repository root from: $common_dir"
managed_root=$repo_root/.worktrees

current_top=
if current_candidate=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null); then
  current_common=$(git -C "$current_candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ "$current_common" = "$common_dir" ]; then
    current_top=$(canonical_dir "$current_candidate" 2>/dev/null || true)
  fi
fi

repo_slug=$(cd "$repo_root" && gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) \
  || die 'cannot resolve the GitHub repository (run `gh auth status`)'
[ -n "$repo_slug" ] || die 'GitHub repository name is empty'

snapshot=$(mktemp "${TMPDIR:-/tmp}/astack-worktrees.XXXXXX")
trap 'rm -f "$snapshot"' EXIT INT TERM
git -C "$repo_root" worktree list --porcelain > "$snapshot"

SAFE=0
CLEANED=0
SKIPPED=0
ERRORS=0
MATCHED=0
worktree_path=
worktree_head=
worktree_branch=

skip_worktree() {
  reason=$1
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP\t%s\t%s\t%s\n' "$worktree_branch" "$worktree_path" "$reason"
}

process_worktree() {
  [ -n "$worktree_path" ] || return 0

  branch=$worktree_branch
  case "$branch" in
    refs/heads/*) branch=${branch#refs/heads/} ;;
    '')
      if [ -n "$BRANCH_FILTER" ]; then return 0; fi
      skip_worktree 'detached HEAD'
      return 0
      ;;
    *)
      if [ -n "$BRANCH_FILTER" ]; then return 0; fi
      skip_worktree 'unsupported branch reference'
      return 0
      ;;
  esac

  worktree_branch=$branch
  if [ -n "$BRANCH_FILTER" ] && [ "$branch" != "$BRANCH_FILTER" ]; then
    return 0
  fi
  MATCHED=$((MATCHED + 1))

  canonical_path=$(canonical_dir "$worktree_path" 2>/dev/null || true)
  if [ -z "$canonical_path" ]; then
    skip_worktree 'path is missing or unreadable'
    return 0
  fi
  worktree_path=$canonical_path

  case "$canonical_path" in
    "$managed_root"/*) ;;
    *)
      if [ -n "$BRANCH_FILTER" ]; then
        skip_worktree 'not inside the managed .worktrees directory'
      else
        MATCHED=$((MATCHED - 1))
      fi
      return 0
      ;;
  esac

  if [ -n "$current_top" ] && [ "$canonical_path" = "$current_top" ]; then
    skip_worktree 'current worktree; move the session to the primary checkout first'
    return 0
  fi

  if [ -n "$(git -C "$canonical_path" status --porcelain 2>/dev/null)" ]; then
    skip_worktree 'working tree is not clean'
    return 0
  fi

  local_head=$(git -C "$canonical_path" rev-parse HEAD 2>/dev/null || true)
  if [ -z "$local_head" ] || [ "$local_head" != "$worktree_head" ]; then
    skip_worktree 'cannot verify the local HEAD'
    return 0
  fi

  remote=$(git -C "$repo_root" config --get "branch.$branch.remote" 2>/dev/null || true)
  if [ -n "$remote" ] && [ "$remote" != '.' ]; then
    if ! remote_rows=$(git -C "$repo_root" ls-remote "$remote" "refs/heads/$branch" 2>/dev/null); then
      ERRORS=$((ERRORS + 1))
      skip_worktree "cannot query remote branch from $remote"
      return 0
    fi
    remote_head=$(printf '%s\n' "$remote_rows" | awk 'NR == 1 { print $1; exit }')
    if [ -n "$remote_head" ] && [ "$remote_head" != "$local_head" ]; then
      skip_worktree 'remote branch contains a different HEAD'
      return 0
    fi
  fi

  if ! pr_rows=$(cd "$repo_root" && gh pr list \
      --repo "$repo_slug" --head "$branch" --state merged --limit 100 \
      --json number,state,mergedAt,headRefName,headRefOid,baseRefName,url \
      --jq '.[] | [.number, .state, (.mergedAt // ""), .headRefName, .headRefOid, .baseRefName, .url] | @tsv' 2>/dev/null); then
    ERRORS=$((ERRORS + 1))
    skip_worktree 'cannot query GitHub pull requests'
    return 0
  fi

  pr_row=$(printf '%s\n' "$pr_rows" | awk -F '\t' -v branch="$branch" -v oid="$local_head" '
    $2 == "MERGED" && $4 == branch && $5 == oid { print; exit }
  ')
  if [ -z "$pr_row" ]; then
    skip_worktree 'no merged PR exactly matches this branch and HEAD'
    return 0
  fi

  pr_number=$(printf '%s\n' "$pr_row" | awk -F '\t' '{ print $1 }')
  pr_url=$(printf '%s\n' "$pr_row" | awk -F '\t' '{ print $7 }')
  SAFE=$((SAFE + 1))

  if [ "$MODE" = audit ]; then
    printf 'SAFE\t%s\t%s\tPR #%s\t%s\n' "$branch" "$canonical_path" "$pr_number" "$pr_url"
    return 0
  fi

  if ! git -C "$repo_root" worktree remove -- "$canonical_path"; then
    ERRORS=$((ERRORS + 1))
    printf 'ERROR\t%s\t%s\tworktree removal failed\n' "$branch" "$canonical_path" >&2
    return 0
  fi
  if ! git -C "$repo_root" branch -D -- "$branch" >/dev/null; then
    ERRORS=$((ERRORS + 1))
    printf 'ERROR\t%s\t%s\tworktree removed but local branch deletion failed\n' "$branch" "$canonical_path" >&2
    return 0
  fi

  CLEANED=$((CLEANED + 1))
  printf 'CLEANED\t%s\t%s\tPR #%s\t%s\n' "$branch" "$canonical_path" "$pr_number" "$pr_url"
}

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    worktree\ *) worktree_path=${line#worktree } ;;
    HEAD\ *) worktree_head=${line#HEAD } ;;
    branch\ *) worktree_branch=${line#branch } ;;
    '')
      process_worktree
      worktree_path=
      worktree_head=
      worktree_branch=
      ;;
  esac
done < "$snapshot"
process_worktree

if [ "$MODE" = cleanup ]; then
  git -C "$repo_root" worktree prune
fi

printf 'SUMMARY\tmode=%s\tsafe=%s\tcleaned=%s\tskipped=%s\terrors=%s\n' \
  "$MODE" "$SAFE" "$CLEANED" "$SKIPPED" "$ERRORS"

[ "$ERRORS" -eq 0 ] || exit 2
if [ -n "$BRANCH_FILTER" ]; then
  [ "$MATCHED" -gt 0 ] || exit 1
  if [ "$MODE" = cleanup ]; then
    [ "$CLEANED" -gt 0 ] || exit 1
  else
    [ "$SAFE" -gt 0 ] || exit 1
  fi
fi
