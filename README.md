# Agent Stack

A portable multi-agent software delivery workflow for Codex,
Claude Code, Cursor, and OpenCode.

Agent Stack turns an issue or request into a governed workflow:

```text
Request
   ↓
Resolver
   ├─→ Designer
   ↓
OpenSpec
   ↓
Developer
   ↓
Design QA
   ↓
PR
```

Agent Stack also includes browser and mobile QA powered by TypeSafe Jev.

## Install

```sh
curl -fsSL https://github.com/JavierBertolino/agent-stack/releases/latest/download/install.sh | sh
```

## Coding agent installation guides

Agent Stack installs the project integration, but you install the coding-agent
host separately. Use the official guide for the host you plan to use:

- [Claude Code installation and quickstart](https://code.claude.com/docs/en/quickstart)
- [Codex CLI installation and quickstart](https://developers.openai.com/codex/cli/)
- [OpenCode installation and quickstart](https://opencode.ai/docs/)
- [Cursor installation and quickstart](https://cursor.com/docs/get-started/quickstart)

## Initialize a project

```sh
cd my-project
astack init
```

## Verify

```sh
astack doctor
```

## Quick Start

After installing, move into any project and run the interactive wizard:

```sh
cd my-project
astack init
```

The wizard walks through five prompts:

1. **Coding agents** (multi-select) — Codex, Claude Code, Cursor, OpenCode.
2. **Integrations** (multi-select) — Linear, Trello, Maestro, or none.
3. **Specs** (single choice) — Agent Stack uses OpenSpec to create and
   manage implementation specifications. Keep specs in the repository
   (default), or mirror finalized specs to another GitHub repository.
4. **QA** — configure TypeSafe Jev now, or later with `astack auth jev`.
5. **Models** (optional) — every role inherits the active harness model by
   default. Review models and thinking only when asked; large discovered
   catalogs are search-first.

Then verify everything:

```sh
astack doctor
```

## How Agent Stack Works

- `resolver`: primary delivery manager and sole user-facing coordinator.
- `designer`: UX proposal writer for user-facing changes.
- `design-qa`: read-only, adversarial UI/UX review gate.
- `developer`: OpenSpec implementer with task-level verification evidence.
- `web-qa` / `mobile-qa`: standalone browser / Maestro QA judged by Jev.

The resolver owns preflight, clarification, OpenSpec artifacts, delegation,
evidence, specification publication, and closeout. The target project's
`AGENTS.md`, `UX_AGENTS.md`, and `UI_AGENTS.md` stay authoritative for
project-specific rules.

## Agents

Role prompts are platform-neutral; the installer renders platform-specific
frontmatter and keeps generated files safe to synchronize. Supported
platforms: OpenCode, Claude Code, Codex, and Cursor.

## Skills

Canonical skills (`project-context`, `linear-workflow`,
`governance-bootstrap`, `openspec-workflow`, `ux-design`, `implementation`,
`ui-review`, `git-delivery`) are mirrored per platform and verified by
`astack check` and `astack doctor`.

## OpenSpec

Agent Stack uses OpenSpec to create and manage implementation
specifications. `SPECS_MODE=local` (default) keeps specs in the code
repository with no external repository required. `SPECS_MODE=mirror`
publishes the ready spec to another GitHub repository before
implementation. See [docs/openspec.md](docs/openspec.md).
For OpenSpec installation and usage, see its [official installation guide](https://github.com/Fission-AI/OpenSpec/blob/main/docs/installation.md).

## Jev QA

`web-qa` and `mobile-qa` evaluate checkpoints with TypeSafe Jev across
functional, view, and project-agnostic business dimensions (business
rules, side effects, state transitions, traceability).

Configure Jev during `astack init`, or later with:

```sh
astack auth jev
```

Supported routes: TypeSafe direct, Vercel AI Gateway, and
Cloudflare-compatible gateways. Credentials are stored user-level
(`~/.config/astack/env`) and never in a repository.

New to Jev? Read [TypeSafe's Jev introduction](https://docs.typesafe.ai/introduction)
and [quick start](https://docs.typesafe.ai/introduction/quickstart). For
Agent Stack-specific configuration, see [docs/jev.md](docs/jev.md).

## Integrations

Linear, Trello, and Maestro are all opt-in and can be combined freely
(or skipped entirely). OAuth and credentials remain managed by the target
tool and are never written by this kit. Start with the [Linear start guide](https://linear.app/docs/start-guide)
or [Trello getting-started guide](https://www.trello.com/guide), then see
[docs/integrations.md](docs/integrations.md) for Agent Stack configuration.

## Configuration

The installer copies `.agent-stack/defaults.conf` to the project's
`.agent-stack/config.conf` on first initialization. See
[docs/configuration.md](docs/configuration.md) for every setting,
including platforms, integrations, spec publication, models, and Jev
provider routing.

## Updating

`astack update` updates the installed CLI and kit (use
`astack update --check` to preview). `astack upgrade` migrates the
current project to the installed kit while preserving customizations.
See [docs/updating.md](docs/updating.md).

## Commands

```sh
astack init          # scaffold and render missing files
astack sync          # render missing or managed files
astack check         # fail when generated files drift
astack doctor        # dependencies, skills, governance, updates
astack auth jev      # configure the Jev QA provider (user-level)
astack update        # update the installed CLI and kit
astack upgrade       # upgrade the current project to the installed kit
astack prune         # remove only safe, stale generated files
astack --version
astack --help
```

## Architecture

See [docs/architecture.md](docs/architecture.md) for the kit layout,
adapter rendering, run state, and the three-way upgrade mechanism.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities. The kit
contains no credentials; Jev keys live user-level and are never logged,
printed, or committed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Author neutral sources once under
`.agent-stack/`; regenerate the standalone distribution with
`scripts/build-installer.sh`; verify with `sh tests/run.sh` and
`scripts/doctor.sh`.
