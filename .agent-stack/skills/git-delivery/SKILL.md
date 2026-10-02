---
name: git-delivery
description: Manage worktrees, specification publication, implementation PRs, and cross-links. Use for branch setup, mirror-mode spec PRs, and delivery closeout.
metadata:
  version: "1.1"
  consumer: resolver
  stage: deliver
---

# Git Delivery

Keep branches, PRs, and publications traceable and reusable across retries.
Record external side effects immediately.

## Procedure

1. Branch setup: inspect `git status`, determine the base branch (an
   explicitly supplied issue, dependency, or parent branch wins), and create
   or reuse a dedicated worktree at `<repo>/.worktrees/<branch-slug>` with
   the implementation branch created from the selected base. Ensure
   `.worktrees/` is ignored before creating the worktree. Never place a
   worktree in `/tmp`, beside the repository, or in the user's home
   directory. Leave unrelated dirty changes in the original checkout
   untouched. Record repo ID, base ref/SHA, worktree root, allowed scope.
2. Mirror mode: after spec readiness and before implementation, create or
   reuse the namespaced spec branch/PR
   (`projects/<owner>/<repo>/changes/<issue-id>-<slug>/`). Record source
   repo, branch, change ID, artifact hashes, commits. Refresh the same PR
   after verified amendments. Failures block; never silently go local.
3. Implementation PRs: commit the verified scoped changes in the supplied
   worktree, push the branch, and create a PR with `gh pr create` using the
   recorded base via `--base`. A feature-branch base stays the base for a
   stacked PR; never default it to `main`. If a PR already exists for the
   branch, update it instead of duplicating. Do not merge automatically.
   Cross-link issue, spec PR, and implementation PRs. Reuse branches/PRs on
   retry; resume discovers existing PRs instead of duplicating them.
4. Base branches other than main (stacked work) retain the recorded base.
5. Post-merge cleanup: only after re-reading the remote PR and observing state
   `MERGED`, move the active session out of the feature worktree and into the
   repository's primary checkout. Run
   `astack worktree cleanup --root <repo-root> --branch <branch>` and record its
   `CLEANED` evidence. The command is the safety boundary: it only removes a
   clean worktree below `.worktrees/` when the local and extant remote branch
   heads exactly match the merged PR head. It removes the local branch but
   never the remote branch. Never substitute `rm -rf`, `git worktree remove
   --force`, or `git branch -D` by hand when the command skips a worktree.
6. If cleanup reports the branch as current, dirty, detached, unpublished,
   unmerged, or SHA-mismatched, stop cleanup and report the exact reason. A
   merged PR does not authorize discarding later or uncommitted work. When
   session relocation is unavailable, provide the exact cleanup command for a
   later invocation instead of deleting the active worktree.

## Output

Branch/PR references with hashes, cross-links, cleanup evidence, and next
action.

## Evidence

PR IDs, branch names, SHAs, observed remote state, and the `SAFE`/`CLEANED`
result from `astack worktree`. Later source revisions invalidate or refresh
publication and cleanup evidence.

## Failure behavior

- Publication failure in mirror mode is a blocker, not a mode switch.
- Never imply continued observation after the session ends; record
  `awaiting_merge` and stop.
