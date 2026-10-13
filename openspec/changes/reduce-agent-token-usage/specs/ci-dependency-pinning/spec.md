## ADDED Requirements

### Requirement: CI-installed tools are version-pinned
`ci.yml` and `release.yml` SHALL install `@fission-ai/openspec` at an exact
version rather than `@latest`, so test results do not change underneath a
commit.

#### Scenario: A breaking OpenSpec release ships
- **WHEN** `@fission-ai/openspec` publishes a major version that changes CLI
  behavior
- **THEN** CI on `main` keeps using the pinned version until the pin is
  updated deliberately

#### Scenario: The pin exists everywhere it is used
- **WHEN** any workflow runs `npm install -g @fission-ai/openspec`
- **THEN** the spec in that command is an exact version, not a range tag

### Requirement: The pin is kept current by automated proposals
`.github/dependabot.yml` SHALL include an `npm` update entry covering the
directory where the pinned spec is declared, so pin bumps arrive as reviewable
pull requests with the existing `chore` commit convention.

#### Scenario: A new OpenSpec version is released
- **WHEN** dependabot detects a newer version than the pin
- **THEN** it opens a pull request labeled `dependencies` that bumps only the
  pinned spec

### Requirement: Pinning does not weaken existing supply-chain controls
Actions SHALL remain SHA-pinned with version comments, and the change SHALL
not introduce an unpinned install path.

#### Scenario: Audit of workflow pins
- **WHEN** `.github/workflows/*.yml` is inspected after the change
- **THEN** every `uses:` is SHA-pinned and every `npm install -g` names an
  exact version
