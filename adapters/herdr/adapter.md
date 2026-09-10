# Herdr delegation adapter (optional)

Herdr support is preserved but kept out of the neutral resolver role. Use
this adapter only when the project selects Herdr dispatch.

## Rule

Neutral roles never contain Herdr commands. When the Herdr adapter is
selected, the resolver's `git-delivery` outcomes (worktrees, branches, PRs)
are dispatched through Herdr by the adapter; the handoff contract and
evidence requirements do not change.

## Dispatch procedure (OpenCode inside Herdr, `HERDR_ENV=1`)

Keep the current pane as the main coordinator and use Herdr as the visible
execution surface for every delegated subagent:

1. Do not pre-start `designer`, `developer`, or `design-qa`. Create a pane
   only when that role is actually being delegated.
2. Split a sibling pane in the current Herdr tab with
   `herdr pane split --current --direction right --cwd "$PWD" --no-focus`.
   Use a down split when the current layout needs a second row. Keep the
   pane ID returned by Herdr and do not focus the new pane.
3. Start the requested role in that pane with a unique name:
   `herdr agent start <name> --kind opencode --pane <pane-id> --timeout 30000 -- --agent <role>`.
4. Send the complete delegation contract to that pane with
   `herdr agent prompt <pane-id> "<contract>" --wait --timeout <milliseconds>`.
   The contract must include the change, artifact paths, repository and
   worktree boundaries, scope, verification commands, remaining budget, and
   the required structured report format.
5. Read the returned report from the same pane with
   `herdr agent read <pane-id>` and verify its evidence before continuing.
   If more information is needed, prompt the same agent again instead of
   creating a hidden task session.
6. Leave delegated panes visible for traceability. Do not close or reuse
   them for a different role during the change.

When Herdr is active, do not silently use the native hidden `task`
delegation path. When Herdr is not active, use the normal platform-native
delegation path.

## Selection

The project opts in explicitly (configuration + installed Herdr runtime).
Without selection, no Herdr behavior is attempted and no Herdr dependency
is required.

## Failure behavior

If a Herdr split, agent start, prompt, or report read fails, stop and
report the failure. Missing Herdr runtime or authorization when selected
is a truthful blocker for the dispatch step. Never fall back to unscoped
direct execution silently.
