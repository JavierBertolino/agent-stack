## Why

The delivered workflow burns context on every agent turn without anyone
measuring it: the resolver's primary prompt is 19,323 B (~4.8k tokens) of
mixed rules and lookup material, ~4.3 KB of which is episodic reference that
belong behind a skill. Worse, that shipped prompt points at two paths that do
not exist in a consuming project (`scripts/run-state.py`,
`docs/PRODUCT_INTENT.md`), so agents spend turns discovering failures instead
of working. There is no size budget anywhere in CI — `tests/test-skills.sh`
caps skills at 500 lines while roles are uncapped — so prompt growth is
invisible and unregressed. Two more gaps compound it: nothing installed in a
consuming project documents the `astack` CLI (the kit's `docs/` never ship),
so agents discover subcommands by trial, and the rendered OpenCode resolver
has no `astack` permission entry, so even the commands its own prompt directs
fall through to a prompt.

## What Changes

- Split the neutral resolver role into always-loaded operating rules and
  on-demand reference (OpenSpec step detail, traceability template, mirror
  publication policy, closeout checklist), moving the reference behind the
  existing `openspec-workflow` / `git-delivery` skills. Target: rendered
  `.opencode/agents/resolver.md` ≤ 14.9 KB (from 19,323 B, a 23% cut) with
  unchanged behavior. The originally targeted 12 KB would require rewriting
  resolver-owned authority sections (§0/§2/§12); that deeper cut is left to a
  follow-up change instead of being blurred into this one.
- Fix two dangling references in shipped roles: replace
  `scripts/run-state.py --root <project> …` with the real entry point
  (`astack run-state …`), and stop pointing at `docs/PRODUCT_INTENT.md` from
  the shipped resolver prompt (either ship the document under
  `.agent-stack/` or remove the pointer).
- Ship a new `astack-ops` skill so a consuming project has an in-repo map of
  the `astack` CLI (the kit's `docs/` are never installed): one line per
  subcommand plus usage moments, deferring to `astack <command> --help` for
  flags so no flag table can drift from `scripts/astack`.
- Add the matching OpenCode permission entries: the resolver's rendered bash
  block allows `astack run-state *`, `astack check *`, `astack doctor *`, and
  `astack validate *`, so the commands the prompt directs stop falling
  through to `"*": ask`. `update`, `upgrade`, and `prune` stay gated.
- Add CI-enforced context budgets: byte budgets for each neutral role and
  each rendered agent file, and a cap on total eager skill-description bytes.
- Make skill-mirror writes verifiable instead of changing them: assert that a
  single-platform install writes exactly one skill root, and make
  `scripts/doctor.sh` report any skill visible through more than one
  discovery root of the same host — identical copies included, which pass
  silently today — while adapter docs state the per-host root mapping
  truthfully.
- Treat `setup.sh` as an unreviewable build artifact: mark it
  `linguist-generated` with a suppressed diff in `.gitattributes`, and state
  in `AGENTS.md` that agents must edit `scripts/setup-agent-stack.sh` and
  regenerate rather than open `setup.sh`.
- Make CI reproducible: pin `@fission-ai/openspec` to an exact version in
  `ci.yml` and `release.yml`, and add an `npm` dependabot entry so the pin
  moves with review.
- Close a test gap: `tests/test-equivalence.sh` also compares the installed
  `scripts/` outputs (`qa/`, `mobile-qa/`), which it currently skips.

No role contract, handoff schema, or run-state schema changes. Permission
changes are additive and scoped: four `astack` allow entries in the rendered
OpenCode resolver, nothing removed or loosened. No breaking change: installed
file layout and command surface stay the same.

## Capabilities

### New Capabilities

- `prompt-size-budgets`: CI-enforced byte/line budgets for neutral roles,
  rendered agent files, and total eager skill descriptions, so prompt growth
  fails a test instead of accruing silently.
- `resolver-prompt-layout`: the resolver prompt loads only always-relevant
  operating rules; episodic reference is reachable on demand through a
  named skill or reference file, with the same instructions available.
- `shipped-path-integrity`: every repository path referenced by a shipped
  role or skill resolves inside the installed project (or is reworded to the
  command that does), verified by a test over the installed tree.
- `skill-mirror-dedup`: mirror writes stay per-enabled-host and are asserted
  as a regression guard, while doctor reports duplicate visibility to one
  host (identical copies included) and the adapter docs state the root
  mapping instead of claiming a dedupe the installer cannot perform.
- `generated-artifact-hygiene`: generated distribution artifacts are marked
  as such for review tooling and explicitly excluded from agent reads, with
  equivalence coverage extended to every installed output.
- `ci-dependency-pinning`: CI-installed third-party tooling is version-pinned
  and kept current by automated update proposals, matching the existing
  SHA-pinning standard for actions.
- `astack-cli-ops`: an installed skill that maps the `astack` CLI surface for
  agents, plus the rendered permission entries that let the directed commands
  actually run.

### Modified Capabilities

<!-- No existing specs in openspec/specs/; every capability above is new. -->

## Impact

- `.agent-stack/roles/resolver.md` and its `write_role_source` heredoc in
  `scripts/setup-agent-stack.sh` (both must change together; regenerated into
  `setup.sh` via `scripts/build-installer.sh`).
- `.agent-stack/skills/openspec-workflow/SKILL.md`,
  `.agent-stack/skills/git-delivery/SKILL.md` absorb the reference material.
- `.agent-stack/roles/*.md` (all six) for path reference fixes, plus a
  `astack-ops` pointer wherever a role directs an `astack` command.
- New `.agent-stack/skills/astack-ops/SKILL.md`, and its registration in
  `SKILL_NAMES` (`scripts/setup-agent-stack.sh`), `SKILLS`/`SKILL_MARKERS`
  (`scripts/build-installer.sh`), `scripts/doctor.sh`,
  `scripts/upgrade-agent-stack.sh`, `.agent-stack/skills/manifest.json`,
  `tests/test-skills.sh`, `tests/test-render-matrix.sh`, and `docs/SKILLS.md`.
- `render_opencode` in `scripts/setup-agent-stack.sh`: four `astack` allow
  entries in the resolver's bash block (asserted by
  `tests/test-render-matrix.sh`).
- `scripts/setup-agent-stack.sh`: `render_skill_mirrors`, reference text in
  embedded role/skill heredocs; regenerated `setup.sh`.
- `scripts/doctor.sh`: duplicate-visibility reporting.
- New `tests/test-prompt-budgets.sh`, new `tests/test-path-integrity.sh`;
  updated `tests/test-equivalence.sh`; all wired through `tests/run.sh`.
- `.gitattributes` (new), `AGENTS.md`, `.github/workflows/ci.yml`,
  `.github/workflows/release.yml`, `.github/dependabot.yml`.
- Consuming projects see the same file layout with smaller prompts; existing
  installs pick the changes up through `astack upgrade`.
