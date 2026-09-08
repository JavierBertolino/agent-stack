# Adapter Capabilities

Policy (neutral prompts) is distinct from enforcement (host permissions).
Use supported permissions and scoped tools where available, and fail closed
on required boundaries. Never claim equivalent protection when an adapter
cannot provide it.

## Enforcement matrix

What each adapter enforces versus what remains prompt policy. Tested by
`tests/test-render-matrix.sh` (file rendering) and `scripts/doctor.sh`
(policy audit); runtime behavior is manual per the matrix below.

| Boundary | OpenCode | Claude Code | Codex | Cursor |
| --- | --- | --- | --- | --- |
| Resolver Skill access | enforced (`skill: allow`) | inherited tools (Skill available) | host-managed | host-managed |
| Designer shell denial | enforced (`bash: deny`) | enforced (no Bash in `tools`) | prompt policy (workspace-write sandbox) | prompt policy |
| Designer ux.md-only writes | enforced (path-scoped edit) | prompt policy (`Write` unscoped) | prompt policy | prompt policy |
| Design-QA read-only | enforced (edit+bash+task deny) | enforced (read-only `tools`) | enforced (`read-only` sandbox) | enforced (`readonly: true`) |
| Skill preload vs access | permissions (not preload) | preload is not an ACL | host-managed | host-managed |
| Mandatory-skill gate | prompt + doctor | prompt + doctor | prompt + doctor | prompt + doctor |

A preload list is not an access-control list anywhere. Missing mandatory
skills block the stage on every host; adapters never weaken that gate.

## Per-host notes

- OpenCode (`adapters/opencode/adapter.md`): supported skill permissions
  per role; discovery through `.opencode/skills/`, `.claude/skills/`, and
  `.agents/skills/`. No hardcoded `.opencode` paths in neutral roles.
- Claude Code (`adapters/claude/adapter.md`): `skills` preload for small
  mandatory procedures; Skill tool retained for on-demand use. Preload is
  not an ACL. `Write` cannot be path-scoped by the tool list, so the
  designer ux.md-only boundary is prompt policy.
- Codex (`adapters/codex/adapter.md`): `.agents/skills/` discovery with
  runtime metadata; coarse `sandbox_mode` (workspace-write except QA
  read-only). Path-scoped write boundaries are prompt policy.
- Cursor (`adapters/cursor/adapter.md`): verify skill discovery and
  subagent support per version; test rendered output.
- Herdr (`adapters/herdr/adapter.md`, optional): neutral roles contain no
  Herdr commands. When selected, delivery outcomes dispatch through Herdr;
  otherwise no Herdr behavior or dependency exists.

## Compatibility

Pin and test the host compatibility matrix separately from file-rendering
snapshots: skill loading (preload + on-demand), subagent and delegation
behavior, permission enforcement, and fresh-worktree resolution. Current
documentation alone does not establish runtime compatibility.

## Verification

- `scripts/doctor.sh`: dependencies, skill frontmatter, manifest,
  contracts, governance status, mirror consistency and collisions.
- `setup check`: rendered files match canonical sources (roles, skills,
  mirrors, configs).
- Fresh-worktree test: install, commit skills, create a worktree, and
  confirm agents, skills, and governance resolve correctly.
