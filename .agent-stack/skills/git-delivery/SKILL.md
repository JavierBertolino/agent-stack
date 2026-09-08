---
name: git-delivery
description: Manage worktrees, specification publication, implementation PRs, and cross-links. Use for branch setup, mirror-mode spec PRs, and delivery closeout.
metadata:
  version: "1.0"
  consumer: resolver
  stage: deliver
---

# Git Delivery

Keep branches, PRs, and publications traceable and reusable across retries.
Record external side effects immediately.

## Procedure

1. Branch setup: inspect `git status`, create the approved branch from the
   recorded base or ask once on dirty trees; record repo ID, base ref/SHA,
   worktree root, allowed scope.
2. Mirror mode: after spec readiness and before implementation, create or
   reuse the namespaced spec branch/PR
   (`projects/<owner>/<repo>/changes/<issue-id>-<slug>/`). Record source
   repo, branch, change ID, artifact hashes, commits. Refresh the same PR
   after verified amendments. Failures block; never silently go local.
3. Implementation PRs: publish scoped changes, cross-link issue, spec PR,
   and implementation PRs. Reuse branches/PRs on retry; resume discovers
   existing PRs instead of duplicating them.
4. Base branches other than main (stacked work) retain the recorded base.

## Output

Branch/PR references with hashes, cross-links, and next action.

## Evidence

PR IDs, branch names, SHAs, and observed remote state. Later source
revisions invalidate or refresh publication evidence.

## Failure behavior

- Publication failure in mirror mode is a blocker, not a mode switch.
- Never imply continued observation after the session ends; record
  `awaiting_merge` and stop.
