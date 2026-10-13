## ADDED Requirements

### Requirement: The resolver prompt separates rules from reference
The neutral resolver role SHALL contain only always-relevant operating rules.
Episodic reference — OpenSpec artifact-by-artifact procedure, the design
traceability template, mirror publication policy details, and the closeout
checklist — SHALL live in a skill or reference file that is loaded on demand.

#### Scenario: Reference material moved out of the resolver role
- **WHEN** the resolver must apply the traceability block format
- **THEN** it loads that format from a named skill or reference file instead
  of having it inlined in its own prompt

#### Scenario: Rendered prompt shrinks without losing instructions
- **WHEN** the kit is rendered for OpenCode
- **THEN** `.opencode/agents/resolver.md` is at or below 14,900 bytes, and
  every instruction that was present before the change is still reachable
  through a named skill or reference file

### Requirement: Moved reference is reachable by name
Each reference document that replaces inlined resolver text SHALL be named in
the resolver prompt with its file or skill name, so the resolver can find it
without searching the repository.

#### Scenario: Resolver needs mirror publication rules
- **WHEN** `SPECS_MODE=mirror` is configured and the resolver reaches the
  publication stage
- **THEN** the resolver prompt names the skill or file that holds the
  publication policy, and opening that name yields the full policy

#### Scenario: No unguided search
- **WHEN** an instruction was moved out of the resolver prompt
- **THEN** the resolver prompt still contains a pointer to where it went

### Requirement: Behavior is preserved
Moving reference material SHALL not change any required step, gate, or
permission of the delivery workflow. The gates this change touches are
enforced by prompt text alone — `scripts/run-state.py` gates phase
transitions but never gates on recorded artifacts — so for those gates,
preserving the rule's text in the shipped prompt preserves the behavior;
proving the model acts on the rule needs a behavioral eval, which design
Non-Goals defers.

#### Scenario: Readiness-gate rule survives the split
- **WHEN** the readiness-gate detail moves out of the resolver prompt into
  `openspec-workflow`
- **THEN** the resolver prompt still states the one-line gate rule — UI work
  must not reach implementation without a ready designer proposal — and
  `openspec-workflow` holds the full gate detail, so a grep of the installed
  tree finds both

#### Scenario: Enforcement code is untouched
- **WHEN** the change's file list is reviewed
- **THEN** `scripts/run-state.py` and every other gate-enforcing code path
  are absent from it, so gate behavior is unchanged by construction

#### Scenario: Contract tests still pass
- **WHEN** `tests/run.sh` runs after the split
- **THEN** rendering, equivalence, and contract tests pass unchanged
