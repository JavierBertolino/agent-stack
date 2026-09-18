# Integrations

Project-management and device integrations are all opt-in and combinable.
Select any combination during `astack init`, or configure non-interactively:

```sh
astack init --mcp linear,maestro
astack init --mcp none
```

Accepted values: `none`, `linear`, `trello`, `maestro`, `both`, or
comma-separated combos (e.g. `linear,trello,maestro`).

## Linear

Remote MCP (`https://mcp.linear.app/mcp` by default). Used by the
resolver for issue intake, ownership, state transitions, and closeout.

## Trello

Remote MCP (`https://mcp.trello.com/mcp`). Registered alongside or
instead of Linear in every enabled platform's config.

## Maestro (mobile-qa)

Local stdio MCP (`maestro mcp`) for the `mobile-qa` agent. Requires the
Maestro CLI plus Java on `PATH`, and a booted emulator or connected
device with the target app installed. The agent stops with exact
remediation when the toolchain, device, or build is missing.

OAuth and credentials remain managed by the target tool and are never
written by this kit.
