## ADDED Requirements

### Requirement: Skill mirrors are written only for enabled hosts
The installer SHALL write a skill mirror only to discovery roots belonging to
hosts that are enabled for the install, and SHALL never write a root for a
disabled host.

#### Scenario: Only OpenCode is enabled
- **WHEN** `astack init --platforms opencode` runs
- **THEN** each skill exists once under `.opencode/skills/<name>/SKILL.md`,
  and no `.claude/skills/`, `.agents/skills/`, or `.cursor/skills/` directory
  is created

#### Scenario: Each enabled host gets its primary root
- **WHEN** `astack init --platforms opencode,claude,codex,cursor` runs
- **THEN** each skill exists under `.opencode/skills/`, `.claude/skills/`,
  `.agents/skills/`, and `.cursor/skills/`, each exactly once

#### Scenario: A disabled host leaves no residue
- **WHEN** a previously multi-platform install is re-run with one platform
  removed
- **THEN** `astack prune`/`setup check` report the stale root as removable
  rather than silently leaving unmanaged skill copies

### Requirement: Doctor reports skills visible through multiple roots of one host
`scripts/doctor.sh` SHALL report, as a warning, any skill discoverable by one
enabled host through more than one discovery root, including when the copies
are byte-identical.

#### Scenario: Identical copies are visible to OpenCode
- **WHEN** OpenCode, Claude Code, and Codex are all enabled, so a skill exists
  in `.opencode/skills/`, `.claude/skills/`, and `.agents/skills/`, and all
  three copies hash the same
- **THEN** `doctor` warns naming the skill and each path, instead of passing
  silently as it does today

#### Scenario: Divergent copies still fail
- **WHEN** two copies of one skill visible to the same host have different
  hashes
- **THEN** `doctor` reports a collision failure as it does today

### Requirement: Adapter documentation matches installer behavior
`adapters/opencode/adapter.md` and `docs/ADAPTER_CAPABILITIES.md` SHALL state
the actual root mapping and acknowledge that enabling a second host whose root
OpenCode also walks yields duplicate visibility that the installer cannot
remove without breaking the second host.

#### Scenario: Documentation check
- **WHEN** the adapter documentation is read after the change
- **THEN** it lists which root each enabled host is served from, and it no
  longer claims the installer deduplicates roots that must stay separate

### Requirement: Hosts remain able to discover every skill
Each enabled host SHALL still discover every installed skill exactly once
through its own primary root after mirrors are managed.

#### Scenario: Fresh worktree
- **WHEN** skills are installed, committed, and a worktree is created
- **THEN** every enabled host discovers each skill, and `setup check` reports
  no drift
