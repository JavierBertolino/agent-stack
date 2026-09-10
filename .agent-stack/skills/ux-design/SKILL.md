---
name: ux-design
description: Write a user flow, states, copy constraints, and acceptance criteria as ux.md. Use when a change affects user-facing behavior, before design.md and tasks.md are finalized.
metadata:
  version: "1.0"
  consumer: designer
  stage: design
---

# UX Design

Produce one UX proposal as `openspec/changes/<change-name>/ux.md`. Never
write implementation code or review implementation.

## Procedure

1. Read applicable repository instructions and the nearest `UX_AGENTS.md`
   and `UI_AGENTS.md`. Follow the project's language, flow, state, and
   acceptance rules.
2. Read the change's OpenSpec instructions and completed artifacts.
3. Write `ux.md` using the project guide's format, or: Problem; User and
   task; Applied principles; Current flow; Proposed flow; States and
   errors; Reused components; Risks; Acceptance criteria.
4. Identify user role, job, primary action, pain, proposed flow, all
   relevant states, reusable patterns, risks, and testable criteria.

## Output

`ux.md` plus a structured report: guidance applied, deviations, blockers.

## Evidence

File path plus the guide sections applied. A proposal citing no guide
section is incomplete.

## Failure behavior

- Missing guide: use existing patterns, record the deviation, invent nothing.
- Revision requires explicit resolver re-invocation and consumes a round.
