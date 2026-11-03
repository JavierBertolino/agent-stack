# Integrations

Project-management and device integrations are all opt-in and combinable.
Select any combination during `astack init`, or configure non-interactively:

```sh
astack init --mcp linear,maestro
astack init --mcp none
```

Accepted values: `none`, `linear`, `trello`, `jira`, `maestro`, `playwright`,
`both`, or comma-separated combos (e.g. `linear,jira,maestro`). Tokens are
additive: each one enables its integration and leaves the others as
configured, while `none` clears all of them. Disabling a managed integration
removes its server entry from the platform config on the next `astack init` or
`astack sync`.

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

## Playwright (web-qa)

Local stdio MCP (`npx @playwright/mcp@<pinned>`) for the `web-qa` agent,
launched through the project's `scripts/qa/pw-run.sh`. Two defaults ride on
that wrapper:

- The browser joins its own memory-capped `systemd-run` scope, so an
  out-of-memory event kills the browser instead of the terminal hosting the
  agent.
- `PLAYWRIGHT_MCP_SANDBOX=1` turns Chromium's OS sandbox on. Playwright
  launches Chromium with `chromiumSandbox: false`, and the Chromium bundled
  with Playwright 1.64.1 (156.0.8078.4) predates the 156.0.8078.73 security
  release of 2026-10-27.

`MCP_PLAYWRIGHT_VERSION` pins the MCP build (default `0.0.84`); MCP builds
below Playwright 1.64 ignore the sandbox variable. `PW_SANDBOX=0` opts out
where the kernel or a container forbids the sandbox, and `PW_BROWSER=chrome`
runs the installed Chrome channel instead of the bundled Chromium. `astack
doctor` reports the pinned version, a wrapper that predates the sandbox
default, and the Chromium version of a project-local Playwright install —
the browser that `npx playwright test` actually runs.

The entry is opt-in: a host that already provides a browser MCP keeps using
it, and `web-qa` still resolves the browser server by name instead of
assuming this one.

OAuth and credentials remain managed by the target tool and are never
written by this kit.
