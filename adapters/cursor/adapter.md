# Cursor adapter

How Agent Stack executes on Cursor. Neutral roles stay in
`.agent-stack/roles/`; this adapter owns format, discovery, tools,
permissions, and delegation.

## Skill discovery

Skills are mirrored from `.agent-stack/skills/` into the project's skill
location by the installer. Verify skill discovery and subagent capabilities
against the supported Cursor version and test the rendered output. Do not
assume its agent and rule formats are interchangeable with other hosts.

Avoid duplicate same-name skills across discovery roots visible to one
host; the installer uses the explicit manifest with collision detection.

## Agent format

Rendered to `.cursor/agents/*.md` with `name`, `description`, optional
`model`, and `readonly: true` for design-qa. Thinking is controlled at the
active model/session level rather than per agent.

## Delegation

The resolver delegates to `designer`, `developer`, and `design-qa` with
the versioned handoff contract. Reports follow `report.schema.json#1`.

## Capability notes (must be pinned and tested)

- Skill discovery and subagent support per supported version.
- Read-only enforcement for the QA role.
- Fresh-worktree availability of skills and agents.
