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
./install.sh --path=/absolute/path/to/your-project
```

SSH users can use the equivalent clone command:

```sh
git clone git@github.com:JavierBertolino/agent-stack.git \
  "$HOME/.local/share/agent-stack"
cd "$HOME/.local/share/agent-stack"
./install.sh --path=/absolute/path/to/your-project
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
  --mcp linear
```

## What It Installs

- `resolver`: primary delivery manager and sole user-facing coordinator.
- `designer`: UX proposal writer for user-facing changes.
- `design-qa`: read-only, adversarial UI/UX review gate.
- `developer`: OpenSpec implementer with task-level verification evidence.
- Project-owned `UX_AGENTS.md` and `UI_AGENTS.md` starter templates.
- Platform-specific agent files for the selected tools.
- Selected Linear and/or Trello MCP entries for enabled platforms.

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
```

The wrapper `install.sh` is equivalent to `init` with this repository as the
kit root.

## Configuration

The installer copies `.agent-stack/defaults.conf` to the consuming project's
`.agent-stack/config.conf` on first initialization. Edit that project-local
file to configure:

- enabled platforms;
- Linear and Trello MCP selection, names, and URLs;
- model and reasoning settings per role and platform;
- Codex concurrency.

On an interactive install, the wizard detects existing harness configuration,
queries the installed OpenCode model catalog when available, and asks for a
model plus thinking setting for each selected role. Claude Code, Codex, and
Cursor do not expose a stable local model-list command, so their wizard steps
offer existing values and accept a model ID or alias directly. Cursor controls
thinking at the active model/session level rather than per agent.

The default MCP selection is Linear on and Trello off. OAuth and credentials
remain managed by the target tool and are never written by this kit.

## Workflow

The intended flow is:

```text
resolver -> designer (UI changes only) -> developer -> design-qa (UI changes)
```

The resolver owns clarification, OpenSpec artifacts, delegation, evidence,
corrective-round limits, and closeout. See
[`docs/AGENT_PIPELINE.md`](docs/AGENT_PIPELINE.md) for the portable workflow
contract. The target project's `AGENTS.md`, `CLAUDE.md`, `UX_AGENTS.md`, and
`UI_AGENTS.md` remain authoritative for project-specific rules.

## Safety

- The renderer never silently overwrites an untracked human-owned file.
- Generated hashes are recorded in `.agent-stack/generated.manifest`.
- Drift is reported by `check` instead of being silently repaired.
- `prune` removes only unchanged files tracked in the generated manifest.
- The kit contains no credentials or project data.
