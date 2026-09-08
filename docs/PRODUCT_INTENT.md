# Product Intent — Agent Stack

Agent Stack installs a project-aware delivery workflow into an existing
repository. A resolver turns a Linear issue or direct request into a scoped
change, loads the relevant skills and project guidance, delegates
user-facing design when needed, prepares OpenSpec artifacts, optionally
publishes a specification PR, and delegates implementation to a developer.
Verification and UI review precede delivery.

Agent Stack also helps a project author and maintain `UX_AGENTS.md` and
`UI_AGENTS.md` from its existing instructions, documentation, and
implementation evidence. These are project governance documents, not
additional autonomous agents.

Keep four delivery roles: resolver, designer, developer, and design-qa. Add
capabilities through skills before adding roles. Use the host's delegation
and permission mechanisms rather than building another execution service.

The resolver starts from an explicit issue or request. A polling service,
webhook listener, distributed queue, or always-running worker is not part
of this iteration.

## Delivery flow

```text
Explicit Linear issue / direct request
  -> preflight dependencies, repository boundaries, and authorizations
  -> intake + scoped repository context
  -> decide UI/UX impact and record the reason
  -> create/resume OpenSpec change and initial proposal
  -> designer proposal when user-facing behavior is affected
  -> finalize required OpenSpec artifacts and verification tasks
  -> create/update specs PR when mirror mode is configured
  -> developer implements in the supplied worktree
  -> verify scoped changes and task evidence
  -> design-qa reviews UI changes using concrete evidence
  -> refresh specification publication when configured
  -> publish implementation PR(s) and cross-link artifacts
  -> move Linear issue to the configured review/PR state
  -> record awaiting_merge and stop
```

Merge observation and archive/completion are a separate invocation, hook,
or existing project process. The resolver does not keep observing after
its session ends. Default archive timing is after verified merge
(`ARCHIVE_STAGE=after-merge`); alternative project policy must be explicit.

Routine human approval of every completed specification is not required.
A spec PR can remain open while implementation proceeds unless the project
explicitly requires its approval (`SPECS_MERGE_GATE`).

A backend-heavy ticket still needs design routing when it changes a
screen, user workflow, terminology, interaction, accessible behavior, or
visible state. Pure internal changes skip designer and design-qa with a
recorded reason.

## Specification publication

- `SPECS_MODE=local` (default): OpenSpec remains in the code repository;
  no external publication is attempted and no specs repository is required.
- `SPECS_MODE=mirror`: requires an explicitly configured `SPECS_REPOSITORY`
  and publication authorization. The ready specification is published to a
  namespaced branch/PR before developer delegation and refreshed after
  verification. Failures block progress; never silently fall back to local.

The code repository's OpenSpec artifacts remain authoritative; the central
repository is a traceable publication mirror.
