# Agent Stack

Portable installer for a bounded resolver, UX designer, design QA, and
developer agent workflow.

The kit supports OpenCode, Claude Code, Codex, and Cursor. Role prompts are
platform-neutral; the installer renders the platform-specific frontmatter or
configuration and keeps generated files safe to synchronize.

## Quick Start

Users who have been granted access can clone this private repository, enter the
kit directory, and install into an existing project with an absolute path:

```sh
gh auth login
gh repo clone JavierBertolino/agent-stack "$HOME/.local/share/agent-stack"
cd "$HOME/.local/share/agent-stack"
./install.sh --path=/absolute/path/to/your-project \
  --specs-repository=OWNER/specs-repository
```

In Git Bash, `pwd` must be the consuming project directory, not the
`agent-stack` checkout. For example:

```sh
cd /c/Users/Name/Documents/my-project
TARGET=$(pwd)
cd /c/Users/Name/.local/share/agent-stack
./install.sh --path="$TARGET"
```

Git Bash paths beginning with `C:/` are also accepted when `cygpath` is
available. WSL paths should use `/mnt/c/...`.

SSH users can use the equivalent clone command:

```sh
git clone git@github.com:JavierBertolino/agent-stack.git \
  "$HOME/.local/share/agent-stack"
cd "$HOME/.local/share/agent-stack"
./install.sh --path=/absolute/path/to/your-project \
  --specs-repository=OWNER/specs-repository
```

Private repository access is the distribution gate. Anyone with repository
read access can install and run the kit; unauthenticated GitHub `curl` or raw
URL installs are intentionally not advertised because private raw URLs require
credentials too.

## Install Without Cloning

The top-level `setup.sh` is self-contained. An authenticated GitHub CLI
session can stream it directly into the target project:

```sh
gh auth login
cd /path/to/your-project
gh api \
  --header 'Accept: application/vnd.github.raw+json' \
  '/repos/JavierBertolino/agent-stack/contents/setup.sh?ref=main' \
  | sh -s -- init --root "$PWD" \
      --platforms opencode,claude,codex,cursor
```

For automation, use a GitHub token with read access to this private repository:

```sh
curl -fsSL \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H 'Accept: application/vnd.github.raw+json' \
  'https://api.github.com/repos/JavierBertolino/agent-stack/contents/setup.sh?ref=main' \
  | sh -s -- init --root "$PWD" \
      --platforms opencode,claude,codex,cursor
```

This mode uses the script's embedded role prompts, templates, and defaults. It
does not require a local kit checkout, but the caller must still authenticate
to GitHub because the repository is private. A request to a plain
`github.com/...` web URL returns the GitHub page, not the script; an
unauthenticated raw/API request is denied.

For a non-interactive install, choose platforms explicitly:

```sh
./install.sh --path=/absolute/path/to/your-project \
  --platforms opencode,claude,codex,cursor
```

## Global Install

To call `agent-stack` directly from any project directory, install it once:

```sh
./install.sh --global                # prefix defaults to $HOME/.local
./install.sh --global --prefix=/opt  # custom prefix
```

This copies the kit to `<prefix>/share/agent-stack` and writes an
`agent-stack` dispatcher to `<prefix>/bin` (an export line is printed when
that directory is not on `PATH`). Afterwards, from any project:

```sh
cd /path/to/your-project
agent-stack init --platforms opencode
agent-stack check
agent-stack doctor
agent-stack upgrade --check
```

Re-run `install.sh --global` from a fresh checkout to update the global
copy to a newer kit revision.

The default install creates missing files only. Existing human-owned files are
preserved. Use `--kit-root` with the main script when the kit is stored at a
different path:

```sh
sh /path/to/agent-stack/scripts/setup-agent-stack.sh init \
  --root "$PWD" \
  --kit-root /path/to/agent-stack
```

The repository checkout workflow is equivalent to:

```sh
./install.sh --path=/absolute/path/to/your-project \
  --platforms opencode,claude,codex,cursor \
  --mcp linear \
  --specs-repository OWNER/specs-repository
```

## What It Installs

- `resolver`: primary delivery manager and sole user-facing coordinator.
- `designer`: UX proposal writer for user-facing changes.
- `design-qa`: read-only, adversarial UI/UX review gate.
- `developer`: OpenSpec implementer with task-level verification evidence.
- Canonical skills (`project-context`, `linear-workflow`,
  `governance-bootstrap`, `openspec-workflow`, `ux-design`,
  `implementation`, `ui-review`, `git-delivery`) mirrored per platform.
- Versioned handoff/report contracts under `.agent-stack/contracts/`.
- Project-owned `UX_AGENTS.md` and `UI_AGENTS.md` starter templates.
- Platform-specific agent files for the selected tools.
- Selected Linear and/or Trello MCP entries for enabled platforms.
- An ignored `.worktrees/` directory for resolver and specs-repository worktrees.

The generated project files are intentionally not stored in this repository.
They belong to the project being configured.

## Commands

Run these from the consuming project, with the kit supplied through
`--kit-root`:

```sh
setup-agent-stack.sh init     # scaffold and render missing files
setup-agent-stack.sh sync     # render missing or managed files
setup-agent-stack.sh check    # fail when generated files drift
setup-agent-stack.sh adopt    # import existing OpenCode role prompts
setup-agent-stack.sh prune    # remove only safe, stale generated files
scripts/doctor.sh             # dependencies, skills, governance, collisions
scripts/upgrade-agent-stack.sh --check  # dry-run safe source migration
scripts/run-state.py --help   # validated run state (init/lock/transition/verify/resume)
```

The wrapper `install.sh` is equivalent to `init` with this repository as the
kit root.

### Herdr + OpenCode

When the resolver is running as OpenCode inside Herdr, its current pane remains
the main coordinator. It creates a sibling pane only when it delegates to
`designer`, `developer`, or `design-qa`, starts that role there, waits for the
structured report, and leaves the pane visible. It does not pre-start idle
roles. Outside Herdr, the normal native delegation workflow is used.

## Configuration

The installer copies `.agent-stack/defaults.conf` to the consuming project's
`.agent-stack/config.conf` on first initialization. Edit that project-local
file to configure:

- enabled platforms;
- Linear and Trello MCP selection, names, and URLs;
- `SPECS_REPOSITORY` and `SPECS_REPOSITORY_BASE_BRANCH` for finalized OpenSpec
  uploads;
- `TASK_STATE_IN_PROGRESS` and `TASK_STATE_IN_PR` for linked Linear task
  transitions;
- model and reasoning settings per role and platform;
- Codex concurrency;
- specification publication (`SPECS_MODE=local|mirror`, repository, merge
  gate) and archive stage. `--specs-repository OWNER/REPO` implies mirror
  mode; local mode (default) needs no specs repository.

On an interactive install, the wizard runs five visible steps: platforms,
MCP integrations, specs repository, model strategy, and final review. It
detects existing harness configuration and keeps current or harness-default
models unless the operator explicitly chooses one model per platform or a
model per role. OpenCode model search uses the local catalog when available;
`gum`/`fzf` provide fuzzy navigation, while the shell fallback remains
available. Cursor controls thinking at the active model/session level rather
than per agent.

The default MCP selection is Linear on and Trello off. OAuth and credentials
remain managed by the target tool and are never written by this kit.

The interactive wizard uses `gum` menus and `fzf` model search when available.
It falls back to POSIX shell prompts when they are not installed. Set
`AGENT_STACK_PLAIN=1` to force the fallback, which is useful in CI or when
testing scripted TTY input.

`SPECS_REPOSITORY` is required during setup. Interactive setup keeps prompting
until a GitHub `OWNER/REPO` value is supplied; non-interactive setup requires
`--specs-repository=OWNER/REPO` or the value in `.agent-stack/config.conf`.

The resolver does not pause for a user specs-review gate. Once the OpenSpec
artifacts are complete, it delegates directly to `developer`. At closeout it
uploads the finalized change to `SPECS_REPOSITORY`, pushes the implementation
branch, and opens a PR against the recorded base branch. A non-default base
branch produces a stacked PR instead of silently targeting `main`.
For linked Linear tasks, the resolver assigns the authenticated user only when
the task has no assignee, preserves an existing assignee, then sets the task to
`In Progress` when work starts and `In PR` after the implementation PRs are
open. It does not mark an open PR as completed.

## Workflow

The intended flow is:

```text
resolver -> designer (UI changes only) -> spec publication (mirror mode only)
  -> developer -> design-qa (UI changes) -> implementation PR(s)
```

The resolver owns preflight, clarification, OpenSpec artifacts, delegation,
evidence, publication, corrective-round limits, and closeout. See
[`docs/PRODUCT_INTENT.md`](docs/PRODUCT_INTENT.md) for product intent and
[`docs/AGENT_PIPELINE.md`](docs/AGENT_PIPELINE.md) for the portable workflow
contract. The target project's `AGENTS.md`, `CLAUDE.md`, linked product
documents, `UX_AGENTS.md`, and `UI_AGENTS.md` remain authoritative for
project-specific rules. `SPECS_MODE=local` (default) needs no external specs
repository; `SPECS_MODE=mirror` publishes the ready spec before
implementation. Run state lives under `.agent-stack/runs/` with the
resolver as sole writer.

## Safety

- The renderer never silently overwrites an untracked human-owned file.
- Generated hashes are recorded in `.agent-stack/generated.manifest`.
- Drift is reported by `check` instead of being silently repaired.
- `prune` removes only unchanged files tracked in the generated manifest.
- Kit revisions propagate through `upgrade-agent-stack.sh` three-way merge;
  customizations survive with visible `.kit-new` conflicts.
- Interrupted runs report partial progress and resume idempotently.
- The kit contains no credentials or project data.

## Development

- Author neutral sources once under `.agent-stack/`; regenerate the
  standalone `setup.sh` with `scripts/build-installer.sh` (CI enforces
  reproducibility with `--check`).
- Run `sh tests/run.sh` for fixture, contract, installer, upgrade,
  equivalence, and render-matrix tests.
- See `docs/RUN_STATE.md` and `docs/UPGRADES.md` for delivery hardening.
