# Agent Stack Kit

This directory contains the reusable role prompts, templates, and setup defaults
used by the Agent Stack installer.

- `roles/` contains platform-neutral resolver, designer, design-qa, and
  developer instructions.
- `templates/` contains scaffolds for project-owned `UX_AGENTS.md` and
  `UI_AGENTS.md` files.
- `defaults.conf` contains safe setup defaults.
- `generated.manifest` records hashes for files managed by the renderer.

Run `install.sh --root /path/to/project` from the kit repository, or run
`scripts/setup-agent-stack.sh init --kit-root /path/to/agent-stack` from a
project root. The setup is idempotent and does not overwrite existing
human-owned files. Interactively it shows a multiselect for the target
platforms (OpenCode, Claude Code, Codex, Cursor); for non-interactive runs use
`--platforms opencode,claude,codex,cursor` or the `--skip-*` flags.

The script is a single self-contained file: role prompts, guide templates, and
defaults are embedded as fallbacks, so you can copy `setup-agent-stack.sh` alone
to another project (or share it) and it still works. When the `.agent-stack/`
kit directory is present, its files are used as overrides.

The bootstrap also registers the configured Linear MCP server
(`LINEAR_MCP_NAME` / `LINEAR_MCP_URL` in the generated `config.conf`) in every
enabled platform's config:
`opencode.jsonc` (OpenCode), `.mcp.json` (Claude), `.cursor/mcp.json` (Cursor),
and `.codex/config.toml` (Codex). Model pinning per role and platform is
configurable in `config.conf`.

Useful commands:

- `scripts/setup-agent-stack.sh sync` renders missing or previously-managed
  platform files.
- `scripts/setup-agent-stack.sh check` fails when generated files drift.
- `scripts/setup-agent-stack.sh adopt` imports existing OpenCode prompts before
  the first `init` when no neutral role sources exist.
- `scripts/setup-agent-stack.sh prune` removes only stale files recorded in the
  manifest and leaves changed files in place.

Use `--install-codex-bridge` only when the project wants the short UX/UI and
Linear guidance block added to `AGENTS.md`. The installer never adds project
business rules; those remain owned by the consuming project.
