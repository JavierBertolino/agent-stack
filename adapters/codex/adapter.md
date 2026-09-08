# Codex adapter

How Agent Stack executes on Codex. Neutral roles stay in
`.agent-stack/roles/`; this adapter owns format, discovery, tools,
permissions, and delegation.

## Skill discovery

Supports the documented `.agents/skills/<name>/SKILL.md` discovery model
(mirrored from `.agent-stack/skills/` by the installer) plus optional
runtime metadata. Test the actual configured subagent and delegation
behavior independently per version; do not assume skill or rule formats are
interchangeable with other hosts.

Avoid duplicate same-name skills across discovery roots visible to one
host; the installer uses the explicit manifest with collision detection.

## Agent format and sandbox

Rendered to `.codex/agents/*.toml` with model, reasoning effort, and
`sandbox_mode` (`workspace-write` except design-qa `read-only`). The
sandbox is coarse: the designer's ux.md-only boundary and the QA read-only
boundary are prompt policy on top of host enforcement, and any gap must be
stated, never claimed as equivalent protection.

## Delegation

The resolver delegates to `designer`, `developer`, and `design-qa` with
the versioned handoff contract. Reports follow `report.schema.json#1`.
Concurrency honors `CODEX_MAX_CONCURRENT_THREADS`.

## Capability notes (must be pinned and tested)

- Skill discovery and subagent capabilities against the supported version.
- Sandbox behavior for workspace-write vs read-only per role.
- Fresh-worktree availability of `.agents/skills/` and `.codex/agents/`.
