# Changelog

All notable changes to Agent Stack are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions
follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `astack-ops` skill: one usage moment per installed CLI subcommand
  (`init`, `sync`, `check`, `doctor`, `auth jev`, `jev ask`, `update`,
  `upgrade`, `prune`, `run-state`, `validate`, `--version`, `--help`),
  deferring to `astack <command> --help` for flags; registered in the
  installer, doctor, upgrade, tests, manifest, and docs.
- Scoped resolver bash permissions for the CLI the prompt directs:
  `astack run-state/check/doctor/validate` are allowed while `update`,
  `upgrade`, and `prune` stay on the `"*": ask` default.
- Prompt-size budgets enforced by `tests/test-prompt-budgets.sh` (resolver
  ≤ 13,800 B neutral and ≤ 14,900 B rendered, other roles ≤ 7,000 B,
  eager skill descriptions ≤ 2,500 B).
- `tests/test-path-integrity.sh`: installed roles and skills may reference
  only paths a fresh install resolves, roles invoke `astack run-state`
  rather than kit-side scripts, docs and roles agree on the entry point,
  and no `astack` reference is orphaned from the `astack-ops` skill.
- `scripts/doctor.sh` warns when one enabled host can discover a skill
  through more than one root (naming skill and paths); differing hashes
  still fail. Single-platform installs are asserted to leave no other
  host's skill roots, and `setup check` reports stale skill roots of
  disabled hosts as removable (`prune` removes them).

### Changed

- Resolver prompt reduced from 18,412 B to 13,636 B (−25.9%): run-state
  command detail lives in `linear-workflow`, the readiness-gate detail in
  `openspec-workflow`, §5.2–§5.4 folded into one pointer paragraph, and §7
  compressed; §2/§9/§10/§12 stay byte-identical.
- Shipped path references fixed: roles run `astack run-state --root …`
  instead of `scripts/run-state.py`, no role cites kit-only
  `docs/PRODUCT_INTENT.md`, and `docs/RUN_STATE.md` names `astack run-state`
  as the installed-project entry point.
- Adapter documentation (`adapters/opencode/adapter.md`,
  `docs/ADAPTER_CAPABILITIES.md`) states the per-host skill root mapping
  and that residual overlap across enabled hosts is expected, replacing the
  claim that the installer deduplicates roots it must keep separate.
- `astack worktree audit` and `astack worktree cleanup` for guarded cleanup of
  Agent Stack-managed worktrees after GitHub confirms the exact PR head was
  merged.
- Resolver closeout now relocates to the primary checkout and records cleanup
  evidence before completing merged work.

- Pin CI OpenSpec tooling to the exact manifest/lockfile version and preserve
  release validation for historical tags that predate the lockfile.

### Fixed

- `astack upgrade --check` now reports project kit-version drift as a pending
  update even when all managed source files already match the installed kit.

## [0.1.4] — 2026-09-29

### Added

- `astack jev ask --request FILE|-` for ad hoc System One evaluation of
  typed `noul`, `choice`, and `score` questions, sharing the zero-dependency
  `ask-jev.ts` caller with the QA agents.
- Request validation for typed Jev calls: question type checks, `criteria`
  shape per type, and 10 MiB request/response limits.
- Offline test coverage for the typed-request transport
  (`tests/test-jev.sh`, `tests/test-jev.mjs`).

### Changed

- `ask-jev.ts` now loads credentials and provider routing from the
  user-level env file (`~/.config/astack/env`, legacy
  `~/.config/agent-stack/env`) and `.agent-stack/config.conf` when they are
  not exported; exported environment variables keep precedence.
- Model precedence is now `--model`, then the request model, then
  `JEV_MODEL`, then `jev-latest`; an explicit `--model` overrides the
  environment.
- Jev requests use a 30-second per-attempt timeout, and HTTP errors are
  reported without echoing response bodies.
- `ask-jev.ts` requires Node.js 22.6+ for native TypeScript stripping.

### Fixed

- Kit version fallbacks no longer drift: `AGENT_STACK_VERSION` in
  `.agent-stack/defaults.conf` and in the installer's embedded defaults now
  match `VERSION` (it had been stuck at 0.1.2 since 0.1.3). Enforced by
  `tests/test-version-consistency.sh`.

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
