# Claude Code adapter

How Agent Stack executes on Claude Code. Neutral roles stay in
`.agent-stack/roles/`; this adapter owns format, discovery, tools,
permissions, and delegation.

## Skill discovery

Project skills live in `.claude/skills/<name>/SKILL.md` (mirrored from
`.agent-stack/skills/` by the installer) and user skills in
`~/.claude/skills/`. Subagents (`.claude/agents/*.md`) may use the
documented `skills` preload field for required small procedures; the full
skill content is injected at startup.

A preload list is not an access-control list: subagents can still invoke
unlisted project, user, and plugin skills through the Skill tool. Mandatory
stage skills must be loaded before the corresponding action regardless of
preload, and missing skills are truthful blockers.

Retain Skill access for on-demand procedures (resolver, developer). Keep
`tools:` boundaries tight per role (designer: Read, Grep, Glob, Write;
design-qa: Read, Grep, Glob; developer: Read, Grep, Glob, Edit, Write,
Bash). A tool list cannot scope `Write` to one path; the ux.md-only
boundary for the designer is policy enforced by the prompt, not by the
host, and must be stated as such.

## Agent format

Rendered to `.claude/agents/*.md` with `name`, `description`, `model`,
`effort`, and `tools` frontmatter, plus optional `skills:` preload for
small mandatory procedures. Test both preload and on-demand paths.

## Delegation

The resolver delegates via the Agent tool to `designer`, `developer`, and
`design-qa` with the versioned handoff contract. Reports follow
`report.schema.json#1`.

## Capability notes (must be pinned and tested)

- Subagent skill loading (preload + on-demand) per configured version.
- Tool availability for background vs foreground subagents.
- Fresh-worktree availability: committed `.claude/skills/` and
  `.claude/agents/` travel with the checkout.
