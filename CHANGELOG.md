# Changelog

All notable changes to Agent Stack are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions
follow [Semantic Versioning](https://semver.org/).

## [0.1.3] — 2026-09-23

### Added

- Optional model review with `--configure-models` and `--skip-models`.
- Harness-default model inheritance with lazy, search-first model discovery.

### Changed

- Unified wizard selectors around Space to choose or toggle and Enter to
  confirm, with `gum`, POSIX TTY, and numbered fallbacks.
- Expanded host, integration, and governance guidance.

### Fixed

- CI secret scanning now checks full git history on pull requests.

## [0.1.2] — 2026-09-18

### Fixed

- Release archive is self-contained again (`install.sh` included), fixing
  the release smoke test.
- Auto-created tags explicitly dispatch the release workflow (tag pushes
  made with `GITHUB_TOKEN` do not trigger workflows on their own).

Note: the `v0.1.1` tag was created by automation but removed before any
release was published from it; `v0.1.0` remains untouched as tag-only.

## [0.1.1] — 2026-09-18

### Fixed

- Install OpenSpec in CI so `astack doctor` and the global-install tests
  pass on runners.

### Changed

- Release pipeline split into read-only validation and write-only
  publishing jobs with verified-artifact handoff.
- Third-party GitHub Actions pinned to commit SHAs.
- Version tags trigger the release workflow automatically; manual dispatch
  kept for re-runs.

## [0.1.0] — 2026-09-18

First public release.

### Added

- Canonical `astack` CLI (`init`, `sync`, `check`, `doctor`, `auth jev`,
  `update`, `upgrade`, `prune`, `--version`, `--help`).
- Public one-line installer from versioned GitHub Releases with SHA-256
  verification and a versioned install layout (`current` symlink, atomic
  switches, previous version retained).
- `astack update` / `update --check` for the installed CLI and kit.
- `astack upgrade` project migration with `old → new` reporting and
  per-project kit-version tracking.
- Interactive `astack init` wizard: multi-select coding agents,
  multi-select integrations (all opt-in), single-choice OpenSpec specs
  screen, and first-class Jev setup with existing-config detection.
- Jev provider routes: TypeSafe direct, Vercel AI Gateway (with
  `noul` → `boolean` normalization), Cloudflare/compatible gateways, and
  OpenRouter (preview-only until its transport is verified).
- User-level credential storage (`~/.config/astack/env`).
- Project-agnostic Jev business checks (`business_rule_respected`,
  `forbidden_side_effects_avoided`, `state_transition_valid`,
  `traceability_present`).
- Rewritten `astack doctor` diagnostics with remediation commands.
- Public README, `docs/` guides, and open-source community files.
- Release CI/CD: tag-triggered releases with full validation and a clean
  install smoke test; secret and public-safety scanning.
