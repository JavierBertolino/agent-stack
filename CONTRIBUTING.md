# Contributing to Agent Stack

## What this repository is

A portable installer that puts a project-aware delivery workflow (resolver,
designer, developer, design-qa, plus standalone web-qa / mobile-qa) into an
existing repository. The kit owns role contracts, skill procedures, adapter
rendering, and delivery tooling. Consuming projects own their product
behavior, `UX_AGENTS.md`, and `UI_AGENTS.md`.

## Rules

- Author neutral sources once under `.agent-stack/` (`roles/`, `skills/`,
  `contracts/`, `resources/`, `templates/`). Never hardcode host paths
  inside neutral roles or skills.
- Regenerate the standalone distribution with
  `scripts/build-installer.sh`; never hand-edit `setup.sh`
  (CI enforces reproducibility).
- Keep `scripts/*.sh` and `install.sh` POSIX `sh` (`sh -n` must pass).
  Python is allowed for `run-state.py`, `validate-contracts.py`,
  `build-installer.sh`, and `build-release.sh` (stdlib only).
- Capabilities before roles: add skills before adding agents.
- Installation is idempotent and never overwrites human-owned files;
  upgrades three-way merge with visible conflicts.
- Generated consuming-project governance (`UX_AGENTS.md`/`UI_AGENTS.md`
  scaffolds and bootstrap drafts) is not this kit's product policy. The
  bootstrap classifies Declared/Observed/Proposed/Unknown and never
  promotes observed code into mandatory rules.
- Keep the public CLI surface small and `astack`-first. `agent-stack`
  remains only as an unadvertised backwards-compatibility alias.
- Never print, log, or commit credentials. Jev keys stay user-level.

## Verify before finishing

```sh
sh tests/run.sh
sh scripts/doctor.sh --root <fixture> --kit-root "$PWD"
python3 scripts/build-installer.sh --kit-root "$PWD" --check
```

## Releases

Releases are cut from SemVer tags (`v*.*.*`). Pushing a tag runs the full
test suite, builds the distribution, smoke-tests a clean install, and
publishes a GitHub Release with `astack.tar.gz`, checksums, and
`install.sh`. See [CHANGELOG.md](CHANGELOG.md).
