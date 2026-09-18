# Architecture

## Kit layout

```text
agent-stack/
├── .agent-stack/
│   ├── roles/        # neutral role prompts (single source of truth)
│   ├── skills/       # canonical skills + manifest
│   ├── contracts/    # handoff / report / run-state / event schemas
│   ├── resources/    # web-qa + mobile-qa Jev helpers
│   ├── templates/    # project scaffolds
│   └── defaults.conf
├── adapters/         # per-platform rendering notes (claude, codex, cursor, opencode, herdr)
├── scripts/
│   ├── astack                 # canonical dispatcher
│   ├── agent-stack            # backwards-compat alias (unadvertised)
│   ├── setup-agent-stack.sh   # init / sync / check / adopt / prune / auth
│   ├── doctor.sh              # diagnostics
│   ├── upgrade-agent-stack.sh # project three-way merge
│   ├── update-agent-stack.sh  # installed kit updates
│   └── ...
├── docs/
├── tests/
└── install.sh                 # public installer + local modes
```

## Rendering

Neutral role sources are rendered per platform (frontmatter, tool
permissions, sandbox modes). Generated files are hashed into
`.agent-stack/generated.manifest`; `astack check` reports drift instead of
silently repairing it; `astack prune` removes only unchanged stale files.

## Run state

Delivery runs live under `.agent-stack/runs/<run-id>/` with the resolver
as sole writer (`scripts/run-state.py` validates transitions and records
evidence and external side effects).

## Upgrades

Kit revisions propagate through three-way merge against base hashes in
`.agent-stack/sources.manifest`: unchanged managed sources update
cleanly, customizations survive with visible `.kit-new` conflicts.
Project `config.conf` is never modified by upgrades; `doctor` surfaces
new defaults instead.
