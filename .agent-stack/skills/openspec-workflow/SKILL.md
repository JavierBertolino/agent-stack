---
name: openspec-workflow
description: Create and finalize OpenSpec change artifacts through installed procedures. Use after intake to specify a change, before implementation.
metadata:
  version: "1.0"
  consumer: resolver
  stage: specify
---

# OpenSpec Workflow

Produce ready artifacts using the installed OpenSpec capabilities, not a
hardcoded command set. Keep upstream skills upstream-owned.

## Procedure

1. Discover installed OpenSpec capabilities and validate the supported
   version/profile during preflight.
2. Create or resume the change; read the artifact graph and per-artifact
   instructions with completed dependencies.
3. Author proposal, design, tasks, specs, and `ux.md` (for UI work, via the
   designer) following the change schema.
4. Every task carries a concrete `verification:` line runnable in under five
   minutes or naming the closest check.
5. Gate: required artifacts, acceptance criteria, task verification, and UI
   design readiness must hold before implementation. Backend-only changes
   record the reason for skipping design.

## Output

Ready artifacts with absolute paths and hashes, acceptance criteria,
verification plan, exclusions, and governance references.

## Evidence

`openspec status` output showing required artifacts done, plus artifact
hashes. Artifact completion alone is not implementation verification.

## Failure behavior

- Missing OpenSpec skill or CLI capability: truthful blocker, never a false
  readiness claim.
- `ux.md` alone establishes no graph dependency; design readiness stays an
  explicit Agent Stack gate, with `ux.md` passed by absolute path.
