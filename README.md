# Agent Stack

Agent Stack is a portable multi-agent software delivery workflow for **Codex, Claude Code, Cursor, and OpenCode**.

It installs project-aware agents, skills, contracts, and QA tooling into an existing repository while keeping project-specific rules in the project itself.

## Install

Install the latest tagged release:

```sh
curl -fsSL https://github.com/JavierBertolino/agent-stack/releases/latest/download/install.sh | sh
```

Make sure `$HOME/.local/bin` is on your `PATH`, then verify:

```sh
astack --version
astack --help
```

## Initialize a project

From any existing project:

```sh
cd /path/to/project
astack init
```

The interactive setup guides you through:

- **Coding platforms** — multi-select Codex, Claude Code, Cursor, and OpenCode.
- **Integrations** — multi-select Linear, Trello, and Maestro.
- **Specs** — Agent Stack uses **OpenSpec**. Choose **Keep specs in this repository** or mirror them to another GitHub repository.
- **Models** — keep platform defaults or configure role-specific models and reasoning.
- **Jev QA** — configure Jev during setup, or skip it and run `astack auth jev` later.

Existing human-owned files are preserved. Agent Stack tracks generated files and reports drift instead of silently overwriting local work.

## Core workflow

```text
request / issue
      |
      v
   resolver
      |
      +--> designer        (when UI/UX work is needed)
      |
      v
   OpenSpec
      |
      v
   developer
      |
      +--> design-qa      (for UI changes)
      |
      v
   implementation PR
```

Standalone `web-qa` and `mobile-qa` agents provide evidence-driven QA with Jev.

## Jev

Jev is a first-class QA engine in Agent Stack.

Configure it interactively:

```sh
astack auth jev
```

If Jev is configured during `astack init`, this command is not needed.

Supported configuration routes:

- **TypeSafe direct** — native System One API.
- **Vercel AI Gateway** — Jev evaluation model through Vercel AI Gateway.
- **Cloudflare AI Gateway / custom gateway** — requires a System One-compatible evaluation endpoint.
- **OpenRouter** — configuration is exposed as preview while Agent Stack verifies the public System One request contract.

Credentials are stored in the user config directory, never in the project repository.

## Commands

```text
astack init                 Configure Agent Stack in the current project
astack sync                 Synchronize managed files
astack check                Detect generated-file drift
astack doctor               Diagnose the installation and project
astack auth jev             Configure Jev provider and credentials

astack update               Update the installed astack CLI/kit
astack update --check       Check whether a new astack release exists
astack upgrade              Upgrade the current project's managed files
astack upgrade --check      Preview project-level upgrades

astack adopt                Adopt existing OpenCode agent prompts
astack prune                Remove safe stale generated files
astack --version            Show the installed version
```

### `update` vs `upgrade`

These are intentionally different:

- `astack update` downloads and verifies the latest **tagged Agent Stack release** and updates the global CLI/kit.
- `astack upgrade` migrates the **current project's managed Agent Stack files** to the installed kit version using the recorded source hashes.

Local customizations are preserved. When a managed source was changed locally, the upgrade writes the new kit version beside it for an explicit merge instead of overwriting it.

## OpenSpec

Agent Stack uses OpenSpec for specification-driven implementation.

During `astack init`:

```text
Specs - Agent Stack uses OpenSpec to create and manage specifications.

1) Keep specs in this repository
   OpenSpec artifacts stay with the project. No external specs repository is required.

2) Mirror specs to another repository
   OpenSpec artifacts remain authoritative here and are also published to a GitHub specs repository.
```

Local mode is the default.

## Agents

| Agent | Responsibility |
| --- | --- |
| `resolver` | Intake, scope, OpenSpec, delegation, verification, and delivery |
| `designer` | UX proposal and user-facing acceptance criteria |
| `developer` | Scoped implementation and verification |
| `design-qa` | Read-only UI/UX review |
| `web-qa` | Browser-driven functional/view/business-rule QA with Jev |
| `mobile-qa` | Maestro-driven mobile QA with Jev |

## Skills

Canonical skills live under `.agent-stack/skills/` and are rendered into the selected coding platforms.

The current stack includes:

- `project-context`
- `linear-workflow`
- `governance-bootstrap`
- `openspec-workflow`
- `ux-design`
- `implementation`
- `ui-review`
- `git-delivery`

Provider-specific integrations are optional. A project can use Agent Stack without Linear, Trello, Maestro, or an external specs repository.

## Updating

Agent Stack releases follow semantic versioning.

Releases are created by GitHub Actions when a `vX.Y.Z` tag is pushed. The release contains:

- `astack.tar.gz`
- `astack.tar.gz.sha256`
- `install.sh`

The bootstrap installer and `astack update` verify the archive checksum before installation.

## Safety

- Human-owned files are never silently overwritten.
- Generated files are recorded in a manifest.
- `astack check` reports drift.
- Project upgrades use recorded source hashes.
- Customized managed files are preserved with visible merge candidates.
- Jev credentials live outside the repository.
- Interrupted setup can be re-run safely.

## Development

Clone the repository and run:

```sh
sh tests/run.sh
python3 scripts/build-installer.sh --kit-root "$PWD" --check
sh scripts/doctor.sh --root "$PWD" --kit-root "$PWD"
```

The standalone `setup.sh` is generated from canonical sources. Do not edit it manually.

See:

- [Product intent](docs/PRODUCT_INTENT.md)
- [Agent pipeline](docs/AGENT_PIPELINE.md)
- [Skills](docs/SKILLS.md)
- [Run state](docs/RUN_STATE.md)
- [Upgrades](docs/UPGRADES.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

MIT.
