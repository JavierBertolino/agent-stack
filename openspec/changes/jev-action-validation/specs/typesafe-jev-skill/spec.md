## ADDED Requirements

### Requirement: The neutral Jev skill and shared validator ship to both QA roles

The kit SHALL ship `.agent-stack/skills/typesafe-jev/SKILL.md` for both
`web-qa` and `mobile-qa`, register and mirror it through all enabled hosts,
and install the shared action-selection resources under `scripts/jev/` during
init and sync. Changed web/mobile question resources SHALL participate in the
normal three-way upgrade merge. New shared gate resources SHALL be installed
missing-only. The skill and validator SHALL not contain host-specific
credentials, paths, product data, or unadapted vendor-specific rules.

#### Scenario: Fresh install includes the skill and gate
- **WHEN** a consuming project runs `astack init` with web/mobile QA enabled
- **THEN** it receives the canonical skill mirrors and both shared validator
  files, and the roles name the skill and gate before their first Jev action

#### Scenario: Upgrade preserves human changes
- **WHEN** an existing project upgrades to this kit version
- **THEN** the skill participates in the normal three-way source merge, and
  changed question resources receive updates or visible conflicts, while new
  shared gate resources are installed missing-only without overwriting
  human-owned files
