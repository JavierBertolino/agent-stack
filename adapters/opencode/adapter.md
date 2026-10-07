# OpenCode adapter

How Agent Stack executes on OpenCode. Neutral roles stay in
`.agent-stack/roles/`; this adapter owns format, discovery, tools,
permissions, and delegation.

## Skill discovery

Install canonical skills to all of (single source of truth is
`.agent-stack/skills/`; the installer mirrors into):

- `.opencode/skills/<name>/SKILL.md` (OpenCode's own primary root)
- `.claude/skills/<name>/SKILL.md` (Claude Code's primary root; OpenCode
  also walks it)
- `.agents/skills/<name>/SKILL.md` (Codex's primary root; OpenCode also
  walks it)

OpenCode walks up from the cwd to the git worktree and loads matching
`skills/*/SKILL.md` under `.opencode/`, `.claude/skills/`, and
`.agents/skills/`. Global definitions under `~/.config/opencode/skills/`,
`~/.claude/skills/`, and `~/.agents/skills/` are also loaded.

Use the explicit manifest (`.agent-stack/skills/manifest.json`) with
collision detection. The installer writes each enabled host's primary root
and never a root for a disabled host: `.opencode/skills/` for OpenCode,
`.claude/skills/` for Claude Code, `.agents/skills/` for Codex,
`.cursor/skills/` for Cursor. Those roots must stay separate for the hosts
they serve, so enabling a second host whose root OpenCode also walks leaves
every skill visible to OpenCode through more than one root — residual
overlap the installer cannot remove without breaking the second host.
`doctor.sh` warns, naming the skill and each path, whenever one host can
discover a skill through several roots, and fails on collisions
(differing hashes).

Fresh worktrees: committed skills under `.agent-stack/skills/` plus rendered
platform mirrors travel with the checkout. Uncommitted setup files in the
original checkout do not appear in fresh worktrees; commit the installed
skills or re-run `sync` inside the worktree.

## Agent format and permissions

Rendered to `.opencode/agents/*.md` with `description`, `mode`, `color`,
`variant`, and `permission:` frontmatter. Supported skill permissions are
rendered per role (resolver/developer: `skill: allow`; designer scoped to
`openspec/changes/**/ux.md`; design-qa read-only deny). Do not hardcode
`.opencode` paths inside neutral roles.

## Delegation

The resolver delegates via the host task/subagent mechanism to `designer`,
`developer`, and `design-qa` with the versioned handoff contract. Reports
follow `report.schema.json#1`.

## Capability notes

- Skill permissions (`allow`/`deny`/`ask`, wildcard patterns) are enforced
  by OpenCode; per-agent overrides live in agent frontmatter.
- A preload list is not an access-control list. Mandatory skills must still
  be loaded before the corresponding action, with missing skills reported
  as blockers.
