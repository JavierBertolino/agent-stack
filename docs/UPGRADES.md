# Upgrades

Updating the kit is not the same as updating installed role sources.
`sync` renders missing or previously-managed platform files but never
touches project-customized neutral sources. Revisions to default roles,
skills, or contracts propagate through an explicit upgrade with a
three-way comparison.

## Base hashes

At install time the installer records kit base hashes in the consuming
project's `.agent-stack/sources.manifest` (`kit-relative-path|sha256`,
add-missing only). These bases let the upgrade distinguish "unchanged
managed source" from "project customization".

## Upgrade

```sh
scripts/upgrade-agent-stack.sh --root <project> --kit-root <kit> --check  # dry run
scripts/upgrade-agent-stack.sh --root <project> --kit-root <kit>          # apply
```

For each managed source (roles, skills, contracts):

- project file equals the new kit file: up-to-date, base re-recorded.
- project file equals the recorded base: unchanged managed source, updated
  safely to the new revision.
- otherwise: the customization is preserved and the new kit content is
  written to `<file>.kit-new` for manual merge. The conflict exits
  nonzero and stays visible until resolved.
- missing project files are added; kit-removed sources are reported and
  the local copy is preserved.

After upgrading, run `setup-agent-stack.sh sync` to re-render platform
mirrors from the new sources, then `check` and `doctor.sh`.

## Config

`config.conf` is never modified by upgrades. New kit defaults surface
through `doctor.sh`, which warns about keys present in the kit
`defaults.conf` but absent from the project `config.conf`. Add them
explicitly when the project wants them.

## Acceptance mapping

- Existing human edits survive upgrades (three-way merge + `.kit-new`).
- Changed code invalidates stale verification (run-state `record-code`
  staleness, enforced by `validate`).
- Retries reuse branches and PRs (external IDs in run state).
- Cancelled setup reports partial progress (exit trap with created-file
  count and resume guidance) instead of implying no filesystem changes.
- Standalone and checkout installations produce equivalent outputs
  (`tests/test-equivalence.sh`; `build-installer.sh --check` in CI).
