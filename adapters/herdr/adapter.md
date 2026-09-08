# Herdr delegation adapter (optional)

Herdr support is preserved but kept out of the neutral resolver role. Use
this adapter only when the project selects Herdr dispatch.

## Rule

Neutral roles never contain Herdr commands. When the Herdr adapter is
selected, the resolver's `git-delivery` outcomes (worktrees, branches, PRs)
are dispatched through Herdr by the adapter; the handoff contract and
evidence requirements do not change.

## Selection

The project opts in explicitly (configuration + installed Herdr runtime).
Without selection, no Herdr behavior is attempted and no Herdr dependency
is required.

## Failure behavior

Missing Herdr runtime or authorization when selected is a truthful
blocker for the dispatch step. Never fall back to unscoped direct
execution silently.
