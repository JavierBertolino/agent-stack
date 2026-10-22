# Integrations

Project-management and device integrations are all opt-in and combinable.
Select any combination during `astack init`, or configure non-interactively:

```sh
astack init --mcp linear,maestro
astack init --mcp none
```

Accepted values: `none`, `linear`, `trello`, `jira`, `maestro`, `both`, or
comma-separated combos (e.g. `linear,jira,maestro`). Tokens are additive: each
one enables its integration and leaves the others as configured, while `none`
clears all of them. Disabling a managed integration removes its server entry
from the platform config on the next `astack init` or `astack sync`.

## Linear

Remote MCP (`https://mcp.linear.app/mcp` by default). Used by the
resolver for issue intake, ownership, state transitions, and closeout.

## Trello

Remote MCP (`https://mcp.trello.com/mcp`). Registered alongside or
instead of Linear in every enabled platform's config.

## Jira

Remote Atlassian MCP (`https://mcp.atlassian.com/v2/mcp`). Connects the
Atlassian MCP server, which provides Jira tools along with other Atlassian
products available to the authenticated account — Atlassian names the server
`atlassian` for that reason, while this kit registers it as `jira` by default
(override with `MCP_JIRA_NAME`). OAuth and credentials remain managed by the
target tool. See Atlassian's [remote MCP setup guide](https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/).
Registered for every enabled platform so agents can use its tools; the resolver
does not route issue intake or closeout through Jira yet.

## Maestro (mobile-qa)

Local stdio MCP (`maestro mcp`) for the `mobile-qa` agent. Requires the
Maestro CLI plus Java on `PATH`, and a booted emulator or connected
device with the target app installed. The agent stops with exact
remediation when the toolchain, device, or build is missing.

OAuth and credentials remain managed by the target tool and are never
written by this kit.
