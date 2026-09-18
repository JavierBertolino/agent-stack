# OpenSpec

Agent Stack uses OpenSpec to create and manage implementation
specifications. The resolver creates the change, authors each artifact
from the installed CLI's schema, and gates implementation on readiness
(acceptance criteria, concrete task verification, and a designer proposal
for UI work).

## Local mode (default)

```ini
SPECS_MODE=local
```

OpenSpec specs remain in the code repository. No external specs
repository is required or attempted.

## Mirror mode

```ini
SPECS_MODE=mirror
SPECS_REPOSITORY=OWNER/REPO
SPECS_REPOSITORY_BASE_BRANCH=main
```

Agent Stack keeps OpenSpec as the source of truth in the code repository
and mirrors finalized specs to another GitHub repository: after
specification readiness and before developer delegation, it creates (or
reuses on retry) a namespaced spec branch/PR against the recorded base
branch. A non-default base branch produces a stacked PR instead of
silently targeting `main`.

The external specs repository is required only for mirror mode.
