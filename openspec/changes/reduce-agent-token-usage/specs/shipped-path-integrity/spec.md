## ADDED Requirements

### Requirement: Installed roles reference only installed paths
Every path referenced by an installed role SHALL resolve inside a freshly
installed project, or SHALL be reworded to name the command that provides the
behavior. This covers repository-relative paths named by
`.agent-stack/roles/*.md` as installed.

#### Scenario: Run-state helper is invoked through the installed CLI
- **WHEN** the resolver role describes creating or transitioning run state
- **THEN** it names `astack run-state …` rather than
  `scripts/run-state.py`, and that command exists after `astack init`

#### Scenario: Kit-only documents are not cited as project files
- **WHEN** a role references a document that the installer does not ship
- **THEN** the reference is removed or rewritten to name the installed
  location under `.agent-stack/`

### Requirement: Path integrity is verified on the installed tree
A test SHALL install the kit into a temporary root and fail when any
repository-relative path named by an installed role or skill is missing from
that install, excluding paths the consuming project is expected to own (for
example `AGENTS.md`, `UX_AGENTS.md`, `openspec/`, and `reports/`).

#### Scenario: A dangling path is introduced
- **WHEN** a role gains a reference to a file the installer does not create
- **THEN** `tests/test-path-integrity.sh` fails and prints the role, the
  path, and the install root

#### Scenario: Project-owned paths are tolerated
- **WHEN** a role references `AGENTS.md` or `UX_AGENTS.md`, which the
  consuming project owns
- **THEN** the test does not report a failure for that path

### Requirement: Documentation and roles agree on the helper entry point
`docs/RUN_STATE.md` and the shipped resolver role SHALL describe the same
invocation for run-state operations.

#### Scenario: Docs and role disagree
- **WHEN** `docs/RUN_STATE.md` documents one command and the resolver role
  documents another
- **THEN** `tests/test-path-integrity.sh` fails for the mismatch
