## ADDED Requirements

### Requirement: An Agent Stack CLI skill ships with every install
The kit SHALL ship a skill named `astack-ops` at
`.agent-stack/skills/astack-ops/SKILL.md`, registered in the installer's
skill list, the embedded skill sources, `.agent-stack/skills/manifest.json`,
`scripts/doctor.sh`, `scripts/upgrade-agent-stack.sh`, and the skill tests,
so every enabled host discovers it exactly once.

#### Scenario: Registered everywhere
- **WHEN** `astack init` installs the kit and `scripts/doctor.sh` runs
- **THEN** `astack-ops` appears in `.agent-stack/skills/manifest.json`, is
  mirrored into each enabled host's skill root, and doctor reports no
  missing or unknown skill

#### Scenario: Format and manifest checks pass
- **WHEN** `tests/test-skills.sh` runs
- **THEN** `astack-ops` passes the name, description-length, manifest-version,
  and 500-line body checks like every other skill

### Requirement: The skill is a command map, not a copy of the CLI
The `astack-ops` body SHALL give a one-line purpose and usage moment for each
`astack` subcommand, and SHALL name `astack <command> --help` as the authority
for flags instead of copying flag tables out of `scripts/astack`.

#### Scenario: Flag tables are not duplicated
- **WHEN** the skill body is reviewed against `scripts/astack`
- **THEN** it contains no per-flag reference copied from the usage heredoc
  and points at `--help` for exact syntax

#### Scenario: Choosing the right command
- **WHEN** an agent needs to detect generated-file drift before delegating
- **THEN** the skill maps that need to `astack check` without the agent
  searching the repository or guessing subcommand names

### Requirement: Rendered agents can run the commands their prompts direct
The rendered OpenCode resolver SHALL allow `astack run-state *`,
`astack check *`, `astack doctor *`, and `astack validate *` in its bash
permission block, so CLI commands named in the prompt do not fall through to
`"*": ask`.

#### Scenario: Run-state runs without prompting
- **WHEN** the resolver runs `astack run-state --root <project> init …` in
  OpenCode
- **THEN** the command matches an explicit allow entry instead of the
  wildcard `ask` default

#### Scenario: Mutating subcommands stay gated
- **WHEN** the resolver runs `astack update`, `astack upgrade`, or
  `astack prune`
- **THEN** no blanket `astack *` allow exists, so the host default (`ask`)
  still applies to install- and tree-mutating commands

#### Scenario: Render matrix asserts the entries
- **WHEN** `tests/test-render-matrix.sh` runs
- **THEN** it asserts the resolver's rendered permission block contains the
  `astack` allow entries

### Requirement: Roles point at the skill where they invoke the CLI
Installed roles that direct `astack` usage SHALL name the `astack-ops` skill
next to the command they direct, so the agent loads the map instead of
discovering subcommands by trial and error.

#### Scenario: Resolver reaches run-state work
- **WHEN** the resolver reaches a stage that records run state
- **THEN** the resolver prompt names `astack-ops` alongside the
  `astack run-state` example

#### Scenario: No orphan CLI references
- **WHEN** any installed role mentions `astack`
- **THEN** it also names `astack-ops`, and `tests/test-path-integrity.sh`
  treats `.agent-stack/skills/astack-ops/SKILL.md` as installed
