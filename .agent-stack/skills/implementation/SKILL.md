---
name: implementation
description: Implement the OpenSpec task list with per-task verification evidence. Use after specification readiness, in the supplied worktree.
metadata:
  version: "1.0"
  consumer: developer
  stage: implement
---

# Implementation

Execute tasks one by one with minimal scoped diffs. Escalate design
problems to the resolver; never rewrite specs.

## Procedure

1. Work in the supplied branch/worktree. Load mandatory handoff skills
   first; record name, path/source, version/hash, and reason for each.
2. Read the apply instructions and every context file, including `ux.md`
   when supplied.
3. For each pending task: change code, run its `verification:` command,
   check the box only after it passes, continue.
4. Ambiguity: assume reasonably, record under Assumptions, continue. True
   blockers (missing artifact, contradictory spec, missing skill,
   environment failure): stop and batch-report.

## Output

Structured report: done tasks, files changed, guidance and skills applied,
commands with results, assumptions, deviations, blockers.

## Evidence

Each checked task names its command and observed result plus the revision
or diff validated. Command strings without results are not evidence.

## Failure behavior

- Missing mandatory skill: blocker, never pretend.
- No commits or spec edits beyond task checkboxes unless explicitly asked.
- Budget exhaustion: blocked or partial outcome, never ship failed gates.
