## ADDED Requirements

### Requirement: Generated distribution artifacts are marked for review tooling
The repository SHALL contain a `.gitattributes` that marks `setup.sh` as
`linguist-generated`, so code review collapses its diff by default instead of
being dominated by generated bulk, while the local `git diff` after
regeneration stays visible for verification (no `-diff`; `build-installer.sh
--check` is the real guarantee).

#### Scenario: A role change regenerates setup.sh
- **WHEN** `scripts/build-installer.sh` rewrites `setup.sh` and the change is
  committed
- **THEN** GitHub shows the file as generated and collapses its diff by
  default

#### Scenario: Reviewers can still inspect it
- **WHEN** a reviewer needs the generated content
- **THEN** the file remains readable and `build-installer.sh --check` still
  proves it matches the neutral sources

### Requirement: Agents are told not to read generated installers
`AGENTS.md` SHALL state that `setup.sh` is a build artifact that must not be
opened or edited directly, and SHALL name the canonical source
(`scripts/setup-agent-stack.sh`) and the regeneration command.

#### Scenario: An agent needs to change installer behavior
- **WHEN** an agent reads `AGENTS.md` before editing installer logic
- **THEN** it is directed to edit `scripts/setup-agent-stack.sh` and run
  `scripts/build-installer.sh`, and is told not to open `setup.sh`

### Requirement: Equivalence testing covers every installed output
`tests/test-equivalence.sh` SHALL compare every file the installer writes,
including `scripts/qa/`, `scripts/mobile-qa/`, and any other installed
top-level output, not only the config, role, and skill trees it compares
today.

#### Scenario: Installed script drifts between checkout and standalone paths
- **WHEN** `scripts/qa/ask-jev.ts` differs between a checkout install and a
  `setup.sh` install
- **THEN** `tests/test-equivalence.sh` fails and names the file

#### Scenario: Equivalent installs pass
- **WHEN** both install paths produce identical trees
- **THEN** the test passes
