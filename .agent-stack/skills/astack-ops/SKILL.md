---
name: astack-ops
description: Operate the installed Agent Stack CLI. Use when a task scaffolds, syncs, audits, updates, cleans merged worktrees, asks Jev through astack, or manages delivery-run state.
metadata:
  version: "1.1"
  consumer: resolver, developer, web-qa, mobile-qa
  stage: ops
---

# Astack Ops

One map for the installed `astack` CLI: the moment each subcommand is the
right tool. `astack <command> --help` is the authority for flags and
syntax — never reconstruct a flag from memory, and never copy flag tables
into prompts, specs, or reports.

## Procedure

1. `astack init` — scaffold and render managed files in a new or adopted project.
2. `astack sync` — render missing or previously managed files after a kit or config change.
3. `astack check` — fail when generated files drift from their canonical sources.
4. `astack doctor` — audit dependencies, skills, governance, and mirrors.
5. `astack auth jev` — store the Jev API key in user-level config, never in the repository.
6. `astack jev ask` — ask Jev a typed question during web-qa verification.
7. `astack update` — fetch a newer kit release; a human approves the install replacement.
8. `astack upgrade` — three-way merge revised kit defaults into this project; prompts before touching tracked files.
9. `astack prune` — remove only stale files recorded in the manifest; prompts before impact.
10. `astack worktree audit` — read-only report of worktrees eligible for safe cleanup.
11. `astack worktree cleanup` — remove only safe worktrees whose exact PR head is merged; never deletes the remote branch.
12. `astack run-state` — validated delivery-run state: init, lock, transition, record, resume, validate.
13. `astack validate` — validate contract JSON against the kit schemas.
14. `astack --version` — print the installed kit version.
15. `astack --help` — usage summary for every subcommand.

## Evidence

Record the subcommand run and its exit status in the step that used it;
run-state calls also record the run id and phase.

## Failure behavior

- A non-zero exit blocks the step that ran it; report command and stderr verbatim.
- Never hand-edit managed files to work around `update`, `upgrade`, or
  `prune` — those commands gate installer-owned changes for a human.
