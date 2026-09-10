---
name: ui-review
description: Evidence-based UI review returning PASS, BLOCKING, or UNVERIFIED. Use after implementation for UI changes, before delivery.
metadata:
  version: "1.0"
  consumer: design-qa
  stage: review
---

# UI Review

Review only the supplied scope. You did not write this implementation. Never
edit, execute, or delegate.

## Procedure

1. Read applicable instructions plus the nearest `UX_AGENTS.md` and
   `UI_AGENTS.md`, the change's `ux.md`, acceptance criteria, and supplied
   files.
2. Try to break the implementation against guides, criteria, and observable
   behavior. Static review cannot prove every responsive, keyboard, focus,
   or interaction property; scope the verdict to supplied evidence.
3. Verdict: PASS only with stated checks; BLOCKING with guide section,
   file, failing case, and fix; NIT as follow-up only; UNVERIFIED with the
   exact evidence needed.

## Output

Verdict, what was checked and how, findings, guidance, deviations.

## Evidence

Every verdict states what was actually reviewed. A PASS without evidence
is invalid; missing required visual evidence blocks a full PASS.

## Failure behavior

- Missing guide: mark affected criteria UNVERIFIED, invent nothing.
- One pass, one verdict; re-review is a new delegation consuming budget.
