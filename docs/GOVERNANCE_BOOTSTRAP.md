# Governance Bootstrap

Canonical names are `UX_AGENTS.md` and `UI_AGENTS.md`. Singular legacy
names are supported only through deliberate discovery and migration; never
create competing copies.

## Lifecycle

1. The installer creates only missing scaffolds and installs the
   `governance-bootstrap` skill and its procedure.
2. An explicitly selected host executes the bootstrap skill. Without a
   host, setup prints the status (`missing`, `scaffold-only`, `draft`,
   `reviewed`) and the precise next command, and reports governance as
   scaffold-only.
3. Bootstrap writes a draft or proposed diff; it never silently overwrites
   human-owned guides. Existing rules stay authoritative while drafts await
   review.
4. Refreshes compare source hashes from `.agent-stack/context/manifest.json`
   and propose targeted changes. Routine tickets never rewrite governance.

The delivery designer keeps its normal ux.md-only boundary. Governance
bootstrap runs in a separate setup context with explicit permission to
propose the guide files.

## Inputs

Read applicable `AGENTS.md`, `CLAUDE.md`, existing UX/UI governance, README
material relevant to the product, and documents explicitly referenced by
these sources or selected in configuration. Inspect representative
components, tokens/styles, routes/flows, and tests. Do not indiscriminately
ingest the repository.

## Evidence vs authority

Every derived statement is exactly one of Declared, Observed, Proposed, or
Unknown/conflicting. Existing code can contain defects and outdated
decisions. Never promote an observed component or color into mandatory
governance merely because it appears frequently.

## Outputs

`UX_AGENTS.md` covers purpose, audience, jobs, vocabulary, flow
principles, hierarchy, errors/recovery, permission-sensitive behavior, and
acceptance. `UI_AGENTS.md` covers component/token sources, layout,
typography, color use, responsive behavior, states, accessibility, reuse,
and visual evidence. Compact provenance goes in
`.agent-stack/context/manifest.json` (source paths, hashes, section
references, review status, generation version). No secrets or wholesale
ticket copies.

## Status detection

`setup init/sync` and `scripts/doctor.sh` report per guide:

- `missing`: file absent.
- `scaffold-only`: content still matches the installer scaffold.
- `draft`: differs from scaffold but unreviewed (no provenance manifest,
  or manifest without reviewed status).
- `reviewed`: provenance manifest records review.
- `stale`: recorded source hashes no longer match current sources (checked
  on refresh; doctor warns when the manifest is absent rather than
  claiming freshness).
