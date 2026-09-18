# AGENTS.md — Agent Stack kit itself

This file governs agents developing the Agent Stack kit. It is not product
policy for consuming projects.

## What this repository is

A portable installer that puts a project-aware delivery workflow (resolver,
designer, developer, design-qa) into an existing repository. The kit owns
role contracts, skill procedures, adapter rendering, and delivery tooling.
Consuming projects own their product behavior, `UX_AGENTS.md`, and
`UI_AGENTS.md`.

## Rules for working here

- Author neutral sources once under `.agent-stack/` (`roles/`, `skills/`,
  `contracts/`). Never hardcode host paths inside neutral roles or skills.
- Keep embedded installer fallback data synchronized with
  `python3 scripts/build-installer.sh --kit-root "$PWD"`.
  Public distribution is release-based through `astack`; there is no standalone
  generated `setup.sh`.
- Keep `scripts/setup-agent-stack.sh` POSIX `sh` (`sh -n` must pass).
  Python is allowed for `run-state.py`, `validate-contracts.py`, and
  `build-installer.sh` (stdlib only).
- Capabilities before roles: add skills before adding agents. Four
  delivery roles stay fixed unless the plan explicitly changes them.
- Installation is idempotent and never overwrites human-owned files;
  upgrades three-way merge with visible conflicts.
- Generated consuming-project governance (`UX_AGENTS.md`/`UI_AGENTS.md`
  scaffolds and bootstrap drafts) is not this kit's product policy. The
  bootstrap classifies Declared/Observed/Proposed/Unknown and never
  promotes observed code into mandatory rules.
- Verify with `sh tests/run.sh`, `scripts/doctor.sh`, and
  `build-installer.sh --check` before finishing.
