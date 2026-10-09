## ADDED Requirements

### Requirement: Neutral roles stay inside a declared size budget
Each file in `.agent-stack/roles/*.md` SHALL be at most 400 lines; the
resolver role SHALL stay at or below 13,800 bytes and every other role at or
below 7,000 bytes. The resolver cap is the measured landing size of the
planned split (13,523 bytes) plus about 277 bytes of pointer-wording
headroom, and it stays consistent with the rendered cap: 13,800 plus the
measured 1,031 bytes of frontmatter (911 B today plus the four `astack`
permission entries) is 14,831, inside the 14,900-byte rendered cap, so source
and rendered budgets cannot disagree. The budgets are declared once in the
budget test, not scattered across scripts.

#### Scenario: A role grows past the budget
- **WHEN** a neutral role exceeds its line or byte budget
- **THEN** `tests/test-prompt-budgets.sh` fails and names the role, its
  measured size, and its budget

#### Scenario: A role within budget
- **WHEN** every neutral role is within its declared budget
- **THEN** `tests/test-prompt-budgets.sh` passes without warnings

### Requirement: Rendered agent prompts stay inside a declared budget
Rendered agent files SHALL be at most 14,900 bytes, bounding each host's
per-turn prompt cost. This covers `.opencode/agents/*.md`,
`.claude/agents/*.md`, `.codex/agents/*.toml`, and `.cursor/agents/*.md`
after rendering, frontmatter and permission blocks included.

#### Scenario: A rendered resolver exceeds the budget
- **WHEN** `setup` renders `.opencode/agents/resolver.md` larger than 14,900
  bytes
- **THEN** `tests/test-prompt-budgets.sh` fails after performing a fixture
  install

#### Scenario: Budget is checked on a real install, not just sources
- **WHEN** the budget test runs
- **THEN** it installs the kit into a temporary root with all platforms
  enabled and measures the rendered files, so frontmatter and permission
  blocks are counted

### Requirement: Eager skill descriptions stay inside a declared total budget
Combined skill descriptions SHALL not exceed 2,500 bytes, keeping the
always-visible skill list small. The sum covers every `description:` value in
`.agent-stack/skills/*/SKILL.md`.

#### Scenario: A description is added that pushes the total over budget
- **WHEN** the combined skill descriptions exceed 2,500 bytes
- **THEN** `tests/test-prompt-budgets.sh` fails and reports the total and the
  largest descriptions

#### Scenario: Existing per-skill limits still apply
- **WHEN** the total is within budget but one description exceeds the
  existing 1,024-character rule
- **THEN** `tests/test-skills.sh` still fails for that skill
