# Skills

Skills are procedures, not credentials or sandboxes. MCP and tool
connections provide access; runtime authorization controls that access.
Installing a skill never implicitly authorizes the actions it describes.

## Catalog

| Skill | Primary consumer | Result |
| --- | --- | --- |
| project-context | All roles | Scoped source map, applicable instructions, evidence and gaps |
| linear-workflow | Resolver | Normalized issue context and verified tracking updates |
| governance-bootstrap | Setup context | Proposed UX/UI governance and source provenance |
| openspec-workflow | Resolver | Ready artifacts through installed OpenSpec procedures |
| ux-design | Designer | User flow, states, copy constraints, component reuse, acceptance criteria |
| implementation | Developer | Scoped implementation using OpenSpec apply and applicable project skills |
| ui-review | Design QA | Evidence-based PASS, BLOCKING, or UNVERIFIED report |
| git-delivery | Resolver | Safe worktrees, specification publication, implementation PRs, cross-links |

Canonical sources live in `.agent-stack/skills/<name>/SKILL.md` with an
Agent Skills `name`/`description` frontmatter matching the directory name.
`manifest.json` records versions. Use additional project skills by task
relevance; do not preload every available skill into every agent.

## Selection and evidence

Mandatory stage skills load before the corresponding action (resolver
preflight lists them per stage). Optional and domain skills are selected
from their declared descriptions and scope. Every report records skill
name, resolved path/source, version or content hash, and why it was used.
Missing mandatory dependencies block the relevant stage; never pretend to
execute a missing skill.

## Upstream OpenSpec

Keep upstream OpenSpec skills upstream-owned. The local OpenSpec
integration discovers installed capabilities and the artifact graph,
selects the appropriate installed procedure, and adds only Agent Stack's
tracking and handoff requirements. Validate the supported version and
profile during preflight. Never hardcode one host's skill path inside
neutral roles.

## Discovery per host

- OpenCode: `.opencode/skills/`, plus `.claude/skills/` and
  `.agents/skills/` project-local; supported skill permissions per role.
- Claude Code: `.claude/skills/` with the `skills` preload field for small
  mandatory procedures; Skill tool retained for on-demand use. Preload is
  not an access-control list.
- Codex: `.agents/skills/` discovery model with runtime metadata; test
  subagent and delegation behavior per version.
- Cursor: project skill location; verify discovery and subagent support per
  version.

The installer mirrors canonical skills into each enabled platform's
primary root with identical content. `scripts/doctor.sh` reports mirrors
that drift from canonical and same-name collisions whose hashes disagree.
Commit installed skills so fresh worktrees resolve them; uncommitted setup
files do not travel into new worktrees.
