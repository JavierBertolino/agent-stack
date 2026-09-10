# Agent Pipeline

This document describes the portable workflow rendered by the Agent Stack kit.
The role prompts under `.agent-stack/roles/` are the operational source of
truth; this document explains how they fit together. See
[`PRODUCT_INTENT.md`](PRODUCT_INTENT.md) for product intent and the
publication policy.

## Roles

| Role | Responsibility | Write boundary |
|---|---|---|
| `resolver` | Intake, preflight, OpenSpec, delegation, evidence, publication, and closeout | Project files according to the host tool's policy |
| `designer` | UX proposal for user-facing changes | `openspec/changes/**/ux.md` only |
| `design-qa` | Adversarial UI/UX review after implementation | Read-only |
| `developer` | Implements OpenSpec tasks and proves each task | Project implementation plus task checkboxes |

The resolver is the only role that communicates with the user. Subagents
return one structured report to the resolver and do not independently expand
scope. The resolver is the sole run-state writer: `.agent-stack/runs/<run-id>/state.json`
plus append-only `events.jsonl`, managed with `scripts/run-state.py`
(`init`, `lock`, `transition`, `record-external`, `record-code`,
`record-verify`, `resume`, `validate`). Transitions are validated, external
side effects are recorded immediately so retries reuse branches and PRs, and
a code change after verification marks prior results stale.

## Flow

1. **Intake**: resolve a linked Linear issue when supplied, or derive a
   change name from free-form input.
2. **Preflight**: confirm required skills, repository boundaries, base
   refs, and authorizations. Missing mandatory dependencies block the
   stage; skills never override authorization or verification.
3. **Clarify**: ask one batched question round for missing scope, repositories,
   UX/UI impact, constraints, and tracking requirements. Do not pause for
   user approval after the artifacts are complete; delegation is immediate.
4. **Ownership/status**: when work begins on a linked issue, assign the
   authenticated Linear user only if it has no assignee (preserve existing
   ones), move the task to `TASK_STATE_IN_PROGRESS`, and record both
   outcomes in the run state.
5. **Branch**: inspect every affected repository, select the explicit base
   branch when one exists, and create the implementation worktree under the
   repository's ignored `.worktrees/` directory. A feature-branch base
   stays the base for a stacked PR.
6. **Specify**: create the OpenSpec proposal, design, tasks, and applicable
   UX proposal. Every task includes a runnable `verification:` line. UI work
   requires design readiness before implementation; backend-only work skips
   design with a recorded reason.
7. **Publish spec (mirror mode only)**: after specification readiness and
   before implementation, create or reuse the namespaced spec PR. Local mode
   skips external publication entirely.
8. **Implement**: immediately delegate to `developer`, who works task by
   task in the supplied `.worktrees/` path and checks each task only after
   its verification passes.
9. **Review**: verify command evidence, changed-file scope, and OpenSpec
   status. For UI changes, delegate `design-qa` and route only `BLOCKING`
   findings to the developer. Missing required evidence is `UNVERIFIED`,
   never an invented PASS.
10. **Publish**: refresh the spec publication when configured, push the
    implementation branch, and create a PR against its recorded base
    (updating an existing PR instead of duplicating; never auto-merge).
11. **Status**: move the linked Linear task to `TASK_STATE_IN_PR` after all
    implementation PRs are open. Leave it there until the PRs are merged.
12. **Close**: archive the completed change, record `awaiting_merge`, and
    stop. Merge observation and archiving are a separate process.

Delegation uses the host-native subagent path, or the Herdr adapter when
that project selects it (see `adapters/herdr/adapter.md`); neutral roles
contain no Herdr commands.

## Governance

The consuming project owns product, security, financial, data, role,
permission, language, and design-system rules. The agents must read
applicable repository instructions and follow their explicit references
instead of importing assumptions from this kit.

For user-facing work, the nearest applicable `UX_AGENTS.md` and
`UI_AGENTS.md` supply focused UX/UI governance alongside — never instead
of — upstream instructions. Sources are classified as Declared, Observed,
Proposed, or Unknown/conflicting; observed code patterns are never promoted
into mandatory policy, and genuine conflicts are surfaced to the user.

For money-affecting work, the consuming project's financial and register
rules remain binding. Specs must define traceability, cash impact, correction,
reconciliation, and reporting surfaces before implementation is accepted.

## Corrective Budget

Each change has a shared budget (`MAX_CORRECTIVE_ROUNDS`, default 3) across
design, implementation, QA fixes, and re-review. Initial proposal and initial
implementation are not corrective rounds. Every corrective round is recorded
in the run state (`.agent-stack/runs/<run-id>/`).

Active work is time-boxed (`TIMEBOX_MINUTES`, default 25 minutes per change).
When the budget or time-box is exhausted, the resolver offers exactly one of:

- ship as-is and log a follow-up;
- one user-authorized extra round;
- drop the change without destructive reverts.

Budget exhaustion is a blocked or partial outcome, never permission to ship
failed safety, correctness, or required verification gates.

## Platform Rendering

The installer renders the same role bodies into:
- `.opencode/agents/*.md` with OpenCode metadata and permissions;
- `.claude/agents/*.md` with Claude Code metadata and tool boundaries;
- `.codex/agents/*.toml` with Codex model, effort, and sandbox settings;
- `.cursor/agents/*.md` with Cursor metadata and read-only QA marking.

Canonical skills (`.agent-stack/skills/`) are mirrored per enabled
platform (`.opencode/skills/`, `.claude/skills/`, `.agents/skills/`,
`.cursor/skills/`) with identical content; `doctor.sh` reports drift and
collisions. Handoffs and reports follow
`.agent-stack/contracts/handoff.schema.json#1` and `report.schema.json#1`.
See `docs/SKILLS.md` and `docs/ADAPTER_CAPABILITIES.md`.

It also writes project-local platform configuration and optionally registers
the selected Linear and Trello MCP servers. Credentials and OAuth state remain
outside the repository files generated by this kit.

Policy (neutral prompts) is distinct from enforcement (host permissions).
The renderer uses supported permissions and scoped tools where available and
must not claim equivalent protection when an adapter cannot provide it.

## Target-Project Files

The consuming project owns and reviews these files after installation:

```text
.agent-stack/
  config.conf
  generated.manifest
  roles/
  skills/
  contracts/
  context/
  runs/
  templates/
.opencode/agents/
.opencode/skills/
.claude/agents/
.claude/skills/
.codex/agents/
.agents/skills/
.cursor/agents/
.cursor/skills/
UX_AGENTS.md
UI_AGENTS.md
```

Edit neutral role behavior under `.agent-stack/roles/` first, then run
`sync`. Do not hand-edit generated platform mirrors unless the target project
is intentionally replacing the kit's renderer. Upgrades preserve local edits
to managed sources and surface conflicts instead of silently overwriting
them.
