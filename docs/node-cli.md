# Node CLI

`astack init` and `npx agent-stack init` parse arguments in Node, then call `scripts/setup-agent-stack.sh` to write files.

## What Node owns

- Argument parsing and flag checks. Unknown platforms and MCP ids exit 1 before any file is written.
- The terminal prompts for coding agents and integrations (`@clack/prompts`). Ctrl-C cancels and exits 130.
- Non-interactive runs. With no `--platforms`, Node prints the platforms it will use and passes that list to the shell.
- The integrations table in `packages/cli/src/catalog.ts`. Linear, Trello, and Maestro are rendered by the shell. Jira is in the table and is not passed to the shell until a renderer exists.

## What stays in shell

`scripts/setup-agent-stack.sh` still creates scaffolds, renders agents and skills, merges MCP config, prunes, and uninstalls. It also still owns the specs, Jev, and model prompts when you run that script directly without `--platforms`.

`astack doctor`, `update`, `upgrade`, `auth jev`, `jev`, `worktree`, `run-state`, and `validate` stay on the shell dispatcher.

A Node init passes explicit `--platforms` and `--mcp`, so the shell does not ask those questions again. Specs stay in this repository, Jev stays unconfigured, and models stay on the harness default. Use `--specs-mode`, `--specs-repository`, and `astack auth jev` when you want the other choices.

## Next steps

1. Move the specs, Jev, and model prompts into the Node wizard.
2. Teach the shell renderer a Jira MCP token, then flip that catalog row from `shellToken: null` to a real token.
3. Publish the `agent-stack` package so `npx agent-stack init` resolves from the registry. The package is ready to pack. This repository does not publish it yet.
