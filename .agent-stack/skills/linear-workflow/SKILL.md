---
name: linear-workflow
description: Normalize Linear issue context and verify tracking updates. Use when a Linear issue is linked, for intake, traceability, and closeout.
metadata:
  version: "1.0"
  consumer: resolver
  stage: intake-closeout
---

# Linear Workflow

Turn a Linear issue identifier into normalized context and keep tracking
updates verifiable. Never hardcode an MCP server name.

## Procedure

1. Resolve the issue through the connected Linear MCP using its available
   tools. Read description and comments only as needed for scope.
2. Normalize: project name and id, team, issue identifier and URL, cycle,
   milestone, branch name, repository, acceptance criteria, closeout
   requirements. Use `none` for unavailable values; never guess.
3. Preserve existing assignees. An open PR is not completed work.
4. On closeout, move the issue to the configured review/PR state and attach
   closing evidence (scope, verification, branches, files, rounds used).

## Output

Normalized issue context plus, on close, the state transition and evidence
comment references.

## Evidence

Record Linear IDs, URLs, and the observed state before and after each
update. A claimed update without an observed result is not evidence.

## Failure behavior

- No connected Linear MCP and an issue is linked: blocker, stop and report.
- Missing project metadata: ask the user before creating documents.
- Update fails: record the failure visibly; do not claim sync succeeded.
