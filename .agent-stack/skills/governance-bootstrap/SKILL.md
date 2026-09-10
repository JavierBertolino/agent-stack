---
name: governance-bootstrap
description: Derive draft UX/UI governance from project instructions and implementation evidence. Use during setup when UX_AGENTS.md or UI_AGENTS.md is missing, scaffold-only, or stale.
metadata:
  version: "1.0"
  consumer: setup
  stage: setup
---

# Governance Bootstrap

Propose project governance without overwriting human-owned guides. Separate
evidence from authority.

## Inputs

Read applicable `AGENTS.md`, `CLAUDE.md`, existing UX/UI governance, README
material relevant to the product, and documents explicitly referenced by
these sources or selected in configuration. Inspect representative
components, tokens/styles, routes/flows, and tests. Do not indiscriminately
ingest the repository.

## Classification (mandatory)

Every derived statement is exactly one of:

- Declared: supported by an authoritative instruction or approved document.
- Observed: present in implementation, not automatically mandatory.
- Proposed: a recommendation requiring project adoption.
- Unknown/conflicting: unresolved; retain the gap and source references.

Never promote an observed component or color into mandatory governance
merely because it appears frequently. Code can contain defects.

## Outputs

- `UX_AGENTS.md`: purpose, audience, jobs, vocabulary, flow principles,
  hierarchy, errors/recovery, permission-sensitive behavior, acceptance.
- `UI_AGENTS.md`: component/token sources, layout, typography, color use,
  responsive behavior, states, accessibility, reuse, visual evidence.
- Provenance in `.agent-stack/context/manifest.json`: source paths, hashes,
  section references, review status, generation version. No secrets.

## Failure behavior

- Writes a draft or proposed diff only; never silently overwrites reviewed
  guides. Existing rules stay authoritative while drafts await review.
- Repository without guides: produce a clearly labeled draft, never invented
  users, tokens, or business rules presented as policy.
- Refresh compares source hashes and proposes targeted changes only.
