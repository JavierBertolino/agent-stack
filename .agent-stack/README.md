# Agent Stack Kit

This directory contains the reusable role prompts, templates, and setup defaults
used by the Agent Stack installer.

- `roles/` contains platform-neutral resolver, designer, design-qa,
  developer, and standalone web-qa and mobile-qa instructions.
- `skills/` contains canonical skill sources plus `manifest.json` (versions).
- `contracts/` contains the versioned handoff and report JSON schemas.
- `context/` (project-local) holds bootstrap provenance when produced.
- `resources/web-qa/` contains the Jev helper (`ask-jev.ts`) and question
  library (`questions.ts`) copied to the project as `scripts/qa/`.
- `resources/mobile-qa/` contains the mobile question library
  (`questions-mobile.ts`) copied to the project as `scripts/mobile-qa/`.
- `generated.manifest` records hashes for files managed by the renderer.
- `runs/` (project-local, ignored) holds resolver-owned run state:
  `<run-id>/state.json` plus append-only `events.jsonl` and `evidence/`.
  Legacy `.opencode/pipeline-state/` ledgers are not used for new runs.
- `sources.manifest` (project-local) records kit base hashes so
  `scripts/upgrade-agent-stack.sh` can three-way merge revised defaults
  without overwriting project customizations.

Run `install.sh --path=/absolute/path/to/project` from the kit repository, or run
`scripts/setup-agent-stack.sh init --kit-root /path/to/agent-stack` from a
project root. The setup is idempotent and does not overwrite existing
human-owned files. Interactively it walks through platforms, MCP integrations,
the specs repository, model strategy, and a final review. `gum`/`fzf` are used
when available, with a POSIX shell fallback; set `AGENT_STACK_PLAIN=1` to force
the fallback. For non-interactive runs use `--platforms opencode,claude,codex,cursor`
or the `--skip-*` flags. Model selection is optional and defaults to current or
harness-default values. It also requires the GitHub `owner/repo` that will
receive finalized OpenSpec changes and its base branch.

The script is a single self-contained file: role prompts, guide templates, and
defaults are embedded as fallbacks, so you can copy `setup-agent-stack.sh` alone
to another project (or share it) and it still works. When the `.agent-stack/`
kit directory is present, its files are used as overrides.

The bootstrap optionally registers Linear and Trello MCP servers in every
enabled platform's config. Their names and URLs are stored in the generated
`config.conf`:
`opencode.jsonc` (OpenCode), `.mcp.json` (Claude), `.cursor/mcp.json` (Cursor),
and `.codex/config.toml` (Codex). Model pinning per role and platform is
configurable in `config.conf`. Set `SPECS_REPOSITORY` and
`SPECS_REPOSITORY_BASE_BRANCH` during setup. The resolver publishes
the finalized change there through a branch and PR.
`TASK_STATE_IN_PROGRESS` and `TASK_STATE_IN_PR` configure the linked Linear
task states used when work starts and when implementation PRs are open. When
work starts, the resolver assigns the authenticated user only if the task has
no assignee and preserves an existing assignee.

Resolver worktrees are always kept under `.worktrees/` in each repository, and
the installer adds that directory to the repository's `.gitignore` without
removing existing entries.

Useful commands:

- `scripts/setup-agent-stack.sh sync` renders missing or previously-managed
  platform files.
- `scripts/setup-agent-stack.sh check` fails when generated files drift.
- `scripts/setup-agent-stack.sh adopt` imports existing OpenCode prompts before
  the first `init` when no neutral role sources exist.
- `scripts/setup-agent-stack.sh prune` removes only stale files recorded in the
  manifest and leaves changed files in place.
- `astack auth jev` configures the Jev provider and credentials in user-level
  config (never in the repository). The same flow is offered during `astack init`.
- When OpenCode runs inside Herdr, the resolver opens sibling panes on demand
  for delegated roles and keeps the main resolver pane visible.

Use `--install-codex-bridge` only when the project wants the short UX/UI and
Linear guidance block added to `AGENTS.md`. The installer never adds project
business rules; those remain owned by the consuming project.
