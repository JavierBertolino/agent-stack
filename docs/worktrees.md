# Worktree lifecycle

Agent Stack creates short-lived worktrees below a repository's ignored
`.worktrees/` directory. Cleanup is a separate post-merge step because PR
approval, closure, and merge are different states.

## Audit

From the primary checkout:

```sh
astack worktree audit
astack worktree audit --branch feature/my-change
```

`audit` is read-only. `SAFE` means every cleanup precondition passed. `SKIP`
includes the reason the worktree was preserved. Use `--root` to target a repo
other than the current directory. With `--branch`, an absent or unsafe branch
exits non-zero so an automated closeout cannot continue.

## Cleanup

After GitHub reports the corresponding PR as `MERGED`:

```sh
astack worktree cleanup --branch feature/my-change
```

The command removes the worktree and local branch only when:

- the path is a direct child of the primary checkout's `.worktrees/` directory;
- it is not the caller's current worktree;
- the working tree has no tracked, untracked, or ignored changes and is attached
  to a local branch;
- GitHub reports a merged PR with the exact branch and local HEAD SHA;
- the remote branch, when discoverable through its configured push remote,
  `remote.pushDefault`, or `origin`, has that same SHA.

The remote branch is never deleted. This avoids coupling local cleanup to the
repository's GitHub branch-retention policy. Worktrees outside `.worktrees/`,
dirty trees, detached heads, open/closed-unmerged PRs, and branches with later
commits are preserved.

Without `--branch`, cleanup scans all managed worktrees and removes every safe
candidate. Targeted cleanup is preferred during resolver closeout because its
non-zero skip behavior makes the corresponding branch an explicit gate.

## Resolver closeout

The resolver does not keep polling after it opens a PR. On a later invocation
it re-reads the PR. Once the PR is observed as merged, the resolver moves its
session to the primary checkout and invokes targeted cleanup. If the harness
cannot relocate the session, it leaves the worktree intact and reports the
exact command for a later invocation.

Do not replace a skipped cleanup with `rm -rf`, `git worktree remove --force`,
or manual forced branch deletion. Resolve the reported reason first.
