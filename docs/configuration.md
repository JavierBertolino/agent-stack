# Configuration

`astack init` copies `.agent-stack/defaults.conf` to the project's
`.agent-stack/config.conf` on first initialization. Edit the project-local
file to configure behavior. The installer never overwrites it.

## Platforms

`ENABLE_OPENCODE`, `ENABLE_CLAUDE`, `ENABLE_CODEX`, `ENABLE_CURSOR`
(`1` = render, `0` = skip). The wizard multi-select overrides these.

## Integrations

```ini
MCP_LINEAR_ENABLED=0
MCP_TRELLO_ENABLED=0
MCP_MAESTRO_ENABLED=0
```

All integrations are opt-in and combinable (Linear + Maestro, Trello +
Maestro, all, or none). `MCP_*_NAME`, `MCP_*_URL`, and
`MCP_MAESTRO_COMMAND` tune registration. OAuth and credentials stay
managed by the target tool.

## Spec publication

```ini
SPECS_MODE=local
SPECS_REPOSITORY=
SPECS_REPOSITORY_BASE_BRANCH=main
```

`local` (default) keeps OpenSpec specs in the code repository and needs no
external repository. `mirror` publishes the ready spec to
`OWNER/REPO` before implementation.

## Jev provider routing

```ini
JEV_PROVIDER=none
JEV_MODEL=jev-latest
JEV_GATEWAY_URL=
```

Provider is `none`, `typesafe`, `vercel`, or `gateway`. This only records
routing — credentials always live user-level (`~/.config/astack/env`).

## Models

Empty model values inherit the active harness model. During `astack init`
the wizard asks before reviewing models; use `--configure-models` to start
the review directly or `--skip-models` to keep harness defaults without
prompting. In the review, Enter keeps the current value, `s` searches a
harness-discovered catalog only on demand, and `c` accepts an arbitrary
model ID or alias. Large catalogs are search-first and never listed in full
by default; only thinking levels are pinned per role.

## Tasks and workflow gates

Codex concurrency (`CODEX_MAX_CONCURRENT_THREADS`), publication/merge gates,
archive stage, and linked-task states (`TASK_STATE_IN_PROGRESS`,
`TASK_STATE_IN_PR`). If a configured task state does not exist for the
team, the resolver stops and asks instead of substituting another state.
