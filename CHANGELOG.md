# Changelog

All notable changes to Agent Stack are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions
follow [Semantic Versioning](https://semver.org/).

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
