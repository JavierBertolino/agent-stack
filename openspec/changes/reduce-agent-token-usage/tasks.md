Delivery split: group 1 is PR #16; groups 2–8 are PR #17. This shared change
must remain unarchived until both implementation PRs are merged. Record the
CI-pin changelog entry in PR #16 only.

## 1. Reproducible CI and generated-artifact hygiene (independent, land first)

- [x] 1.1 Add `package.json` + `package-lock.json` at the repo root with `@fission-ai/openspec` pinned to an exact version (use the version CI resolves today)
- [x] 1.2 Replace `npm install -g @fission-ai/openspec@latest` in `.github/workflows/ci.yml` and `.github/workflows/release.yml` with `npm ci` plus `node_modules/.bin` on `PATH` (append to `$GITHUB_PATH`), keeping `command -v openspec` working for `scripts/doctor.sh`
- [x] 1.3 Add an `npm` block (package-ecosystem `npm`, `directory: "/"`, weekly, `chore` prefix, `dependencies` label) to `.github/dependabot.yml`
- [x] 1.4 Add `.gitattributes` containing `setup.sh linguist-generated` (no `-diff`, so local regeneration diffs stay visible)
- [x] 1.5 Add the "never open `setup.sh`; edit `scripts/setup-agent-stack.sh` or `.agent-stack/**` and regenerate with `scripts/build-installer.sh`" rule to `AGENTS.md`
- [x] 1.6 Extend the candidate list in `tests/test-equivalence.sh` so installed `scripts/qa/` and `scripts/mobile-qa/` outputs are hash-compared, not skipped
- [x] 1.7 Verify: `sh -n` on changed scripts, `shellcheck --severity=error` on touched `.sh` files, and `sh tests/run.sh` passes
- [x] 1.8 Assert pin hygiene so the spec's "Audit of workflow pins" scenario has a check: no `npm install -g …@latest` remains in any workflow, every `uses:` line is still SHA-pinned with a version comment, and the `npm` dependabot entry from 1.3 is present
- [x] 1.9 Make `tests/test-public-release.sh`'s Jev-status check hermetic (force the absent state with `XDG_CONFIG_HOME` and unset `TYPESAFE_API_KEY`/`AI_GATEWAY_API_KEY`/`JEV_GATEWAY_API_KEY`) — discovered as a pre-existing, environment-dependent failure while running 1.7 on a machine with Jev configured

## 2. Context budget test (intentionally red until group 3)

- [x] 2.1 Create `tests/test-prompt-budgets.sh` with budgets as top-of-file variables: neutral role ≤ 400 lines, resolver ≤ 13,800 B (measured plan landing 13,523 B + pointer headroom; 13,800 + 1,031 B frontmatter = 14,831 ≤ the 14,900 B rendered cap), other roles ≤ 7,000 B, rendered resolver ≤ 14,900 B, other rendered agents ≤ 7,500 B, total skill descriptions ≤ 2,500 B
- [x] 2.2 Have the test measure neutral roles and skill descriptions from kit sources, printing measured vs budget for each failure
- [x] 2.3 Have the test do a fixture install (`--root "$TMP"` with `--platforms opencode,claude,codex,cursor --mcp none`) and measure every rendered agent file across `.opencode/agents`, `.claude/agents`, `.codex/agents`, `.cursor/agents`
- [x] 2.4 Confirm the new test is picked up automatically by the `tests/test-*.sh` loop in `tests/run.sh` and that it currently fails on `resolver.md` (red state is the forcing function)

## 3. Split the resolver prompt and de-duplicate against skills

- [x] 3.1 Build the migration table: list each resolver section being shrunk or removed (§3.1, §4, §5, §5.2, §5.3, §5.4, §6, §11.2–§11.5) with its destination skill and the exact destination heading, and keep it in this task list for sign-off

  | Section | Action in resolver | Destination (skill → exact heading) |
  |---|---|---|
  | §3.1 Task status | remove detail; keep pointer (assignee/state rules) + `record-external --key issueState` line | `linear-workflow` → `## Procedure` steps 3–4 |
  | §4 Branch setup | remove worktree-procedure detail; keep base-ref selection, stacked-PR base rule, scope recording | `git-delivery` → `## Procedure` step 1 |
  | §5 steps 1–4 (artifact procedure) | remove; keep sole-writer run-state block + command examples | `openspec-workflow` → `## Procedure` steps 1–3 |
  | §5.2 Task verification contract | remove (execution rule already in developer role §verification) | `openspec-workflow` → `## Procedure` step 4 |
  | §5.3 Design traceability block | move the block, its only home; leave pointer | `linear-workflow` → `## Traceability block` (new heading, added by 3.5) |
  | §5.4 Specification readiness gate | remove detail; keep the one-line UI gate rule | `openspec-workflow` → `## Procedure` step 5 |
  | §6 Publication procedure | remove detail; keep `SPECS_MODE` semantics, block-on-failure rule, `SPECS_MERGE_GATE` note | `git-delivery` → `## Procedure` step 2 |
  | §11.2 Mirror publication/refresh | trim → pointer | `git-delivery` → `## Procedure` step 2 |
  | §11.3 Implementation PR publication | trim → pointer | `git-delivery` → `## Procedure` steps 3–4 |
  | §11.4 Linear state transitions | trim → pointer | `linear-workflow` → `## Procedure` steps 4–5 |
  | §11.5 Closeout Linear document | trim → pointer | `linear-workflow` → `## Procedure` step 5 (document rules added by 3.7) |
- [x] 3.2 Remove §3.1 task-status detail from `.agent-stack/roles/resolver.md`, leaving a pointer naming `linear-workflow` (assignee and state rules) plus the `record-external --key issueState` line
- [x] 3.3 Remove the worktree-procedure detail from §4, keeping base-ref selection, stacked-PR base rule, and scope recording; point at `git-delivery` for worktree creation rules
- [x] 3.4 Remove §5 artifact procedure, §5.2 verification contract, and §5.4 readiness gate detail, keeping the readiness gate as a one-line rule and pointing at `openspec-workflow`
- [x] 3.5 Move the §5.3 design traceability block into `.agent-stack/skills/linear-workflow/SKILL.md` (its only home) and leave a pointer in the resolver
- [x] 3.6 Remove §6 mirror-publication procedure detail, keeping `SPECS_MODE` semantics, the block-on-failure rule, and `SPECS_MERGE_GATE` note; point at `git-delivery`
- [x] 3.7 Trim §11 to the closeout sequence (evidence confirmation, archive policy, follow-ups, validate/lock/summarize) and point at `git-delivery` and `linear-workflow` for publication, PR, and Linear-state procedure
- [x] 3.8 Confirm every remaining pointer names a mandatory skill from the resolver's §2 stage map and the section to apply, and — for each section shrunk or removed in the 3.1 migration table — that the resolver prompt still contains a pointer naming where that instruction went (spec: "No unguided search"); no instruction removed without an in-prompt pointer
- [x] 3.9 Keep resolver-owned content intact: §0 authority rules, §1, §2, §3, §9 + escalation menu, §10, §12, and all run-state command examples
- [x] 3.10 Re-measure `.agent-stack/roles/resolver.md` and rendered `.opencode/agents/resolver.md`; if over budget, trim additional duplicated blocks (do not raise budgets without recording the reason here)
- [x] 3.11 Behavior-preservation audit — the checkable stand-in for the spec's "Readiness-gate rule survives the split" scenario, since behavioral evals are a non-goal: walk the 3.1 migration table and grep the installed tree to confirm each removed block exists at its destination (traceability in `linear-workflow`, publication and PR procedure in `git-delivery`, verification contract and readiness gate in `openspec-workflow`, task status in `linear-workflow`), and that the resolver prompt still states the readiness-gate rule

Measured (final): resolver role `13,728 B / 289 lines` (budget 13,800 B /
400); rendered resolver worst host `14,759 B` opencode (claude 13,942,
codex 14,025, cursor 13,929; budget 14,900); other roles `3,243–6,180 B /
91–148 lines` (budget 7,000 B / 400); eager skill descriptions `1,315 B`
(budget 2,500). `tests/test-prompt-budgets.sh` enforces all four.

## 4. Fix shipped path references

- [x] 4.1 Replace every `scripts/run-state.py --root <project> …` example in `.agent-stack/roles/resolver.md` with `astack run-state --root <project> …`, keeping `--root` explicit
- [x] 4.2 Remove the `docs/PRODUCT_INTENT.md` pointer from the resolver role; confirm `.agent-stack/README.md` remains the on-demand entry for kit intent
- [x] 4.3 Add an "installed project" section to `docs/RUN_STATE.md` naming `astack run-state` as the project-facing entry point, keeping the kit-side `scripts/run-state.py` invocation for kit development
- [x] 4.4 Create `tests/test-path-integrity.sh`: fixture-install the kit, then fail when any repo-relative path in an installed role/skill is missing outside the allowlist (`AGENTS.md`, `CLAUDE.md`, `UX_AGENTS.md`, `UI_AGENTS.md`, `openspec/`, `reports/`, `.agent-stack/config.conf`, `.agent-stack/runs/` — plus the three entries the fixture surfaced: `.agent-stack/context/` (bootstrap provenance, produced on demand), `.worktrees/` (created when a worktree opens), and `.opencode/pipeline-state/` (legacy ledger, deliberately absent))
- [x] 4.5 Add assertions to that test: no installed role contains `scripts/run-state.py`, no installed role references `docs/PRODUCT_INTENT.md`, and the entry point documented in `docs/RUN_STATE.md` matches the one the resolver role documents — both must name `astack run-state`, and the test fails on any mismatch between the two (spec: "Docs and role disagree")
- [x] 4.6 Verify `tests/test-path-integrity.sh` passes against the fixture install and fails if a deliberate dangling path is reintroduced

## 5. Authorize the CLI the prompt directs (design D9)

- [x] 5.1 In `render_opencode` (`scripts/setup-agent-stack.sh:1597`), add `"astack run-state *": allow`, `"astack check *": allow`, `"astack doctor *": allow`, `"astack validate *": allow` to the resolver bash block
- [x] 5.2 Confirm no blanket `"astack *": allow` exists anywhere, so `update`, `upgrade`, and `prune` still hit the `"*": ask` default
- [x] 5.3 Assert the four entries in `tests/test-render-matrix.sh`, and update any snapshot/allow-list assertions that enumerate the resolver's permissions
- [x] 5.4 Confirm other hosts need no change: Claude resolver renders no `bash` tool, Codex/Cursor rely on sandbox modes, and developer/QA roles already have `bash: allow` or `bash: deny`
- [x] 5.5 Note the enforcement row in `docs/ADAPTER_CAPABILITIES.md` if the matrix claims per-role shell boundaries

## 6. Add the `astack-ops` skill (design D8)

- [x] 6.1 Create `.agent-stack/skills/astack-ops/SKILL.md` with frontmatter (`name: astack-ops`, a ~160 B description, `metadata.version: "1.0"`, `consumer: resolver, developer, web-qa, mobile-qa`, `stage: ops`)
- [x] 6.2 Body = one line per subcommand (`init`, `sync`, `check`, `doctor`, `auth jev`, `jev ask`, `update`, `upgrade`, `prune`, `run-state`, `validate`, `--version`, `--help`) with its usage moment, plus the rule that `astack <command> --help` is the authority for flags — no flag tables copied from `scripts/astack`
- [x] 6.3 Hand-write the `write_skill_source` case arm in `scripts/setup-agent-stack.sh` — `astack-ops) cat > "$target" <<'SKILL_ASTACK_OPS_EOF'` … `SKILL_ASTACK_OPS_EOF` — before regenerating: `build-installer.sh:sync_skills()` looks up the literal start pattern per skill and aborts with `block start not found` when the arm is missing
- [x] 6.4 Register the skill in the remaining nine places: `SKILL_NAMES` (`setup-agent-stack.sh:40`), `SKILLS`/`SKILL_MARKERS` (`build-installer.sh:29`), `write_skills_manifest` + installed-file list (`setup-agent-stack.sh:3303`/`:3407`), `doctor.sh:113`, `upgrade-agent-stack.sh:157`, `tests/test-skills.sh:31`, `tests/test-render-matrix.sh:56`, `.agent-stack/skills/manifest.json`, `docs/SKILLS.md` (the manifest heredoc body is regenerated from `manifest.json` by `build-installer.sh`)
- [x] 6.5 Add `astack-ops` to the resolver's §2 mandatory-skill map for stages that invoke the CLI, and name it next to the `astack run-state` example (spec: every role mentioning `astack` also names the skill)
- [x] 6.6 Extend `tests/test-path-integrity.sh` with the "no orphan CLI references" assertion — any installed role or skill that mentions `astack` must also name `astack-ops`, and `.agent-stack/skills/astack-ops/SKILL.md` counts as installed — added here rather than in group 4 so it can only pass once 6.1–6.5 exist
- [x] 6.7 Verify `tests/test-skills.sh` passes (name, description length, manifest version, ≤ 500 lines), `scripts/doctor.sh` reports no unknown/missing skill, and `build-installer.sh --check` passes after regeneration
- [x] 6.8 Confirm the added description keeps total eager skill descriptions ≤ 2,500 B (asserted by `tests/test-prompt-budgets.sh`)

## 7. Skill mirror visibility and documentation truth

- [x] 7.1 Add a single-platform install assertion (in `tests/test-render-matrix.sh` or the budget test) proving `--platforms opencode` creates only `.opencode/skills/` and leaves `.claude/`, `.agents/`, and `.cursor/` skill roots absent
- [x] 7.2 Add a WARN to `scripts/doctor.sh` for any skill discoverable through more than one root of the same enabled host, naming skill and paths, while keeping differing hashes a failure
- [x] 7.3 Confirm the warning prints the multi-host explanation and does not change the doctor exit code on a healthy install
- [x] 7.4 Correct `adapters/opencode/adapter.md` to state the per-host root mapping and that residual overlap across enabled hosts is expected, removing the claim that the installer deduplicates roots it must keep separate
- [x] 7.5 Mirror the corrected wording in `docs/ADAPTER_CAPABILITIES.md` per-host notes
- [x] 7.6 Cover the "disabled host leaves no residue" scenario: assert that an install re-run with a platform removed leaves the old root detectable as stale, and that `astack prune` / `setup check` report it for removal instead of leaving unmanaged skill copies (spec `skill-mirror-dedup`)

## 8. Regenerate, verify, and document

- [x] 8.1 Run `scripts/build-installer.sh` so the embedded role/skill heredocs and `setup.sh` regenerate from the neutral sources
- [x] 8.2 Run `python3 scripts/build-installer.sh --kit-root "$PWD" --check` and confirm it passes
- [x] 8.3 Run the full suite (13 passed, 0 failed; `check-public-safety.sh`
  clean; `doctor.sh` exits 0 with a project root as CI runs it — bare in the
  kit repo it reports the pre-existing "not initialized" failure because the
  kit ships `defaults.conf`, not a project `config.conf`) : `sh tests/run.sh --kit-root "$PWD"`, `scripts/doctor.sh`, and `scripts/check-public-safety.sh --kit-root "$PWD"`
- [x] 8.4 Run a fixture install for each platform combination used in tests (`opencode`, `claude`, `codex`, `cursor`, and all four) and confirm `setup check` reports no drift
- [x] 8.5 Confirm `tests/test-upgrade.sh` shows unmodified roles/skills are replaced and edited ones surface merge conflicts under `astack upgrade`, including the new `astack-ops` skill
- [x] 8.6 Record final measured sizes (neutral role, rendered resolver, total skill descriptions) against budgets in `tasks.md` group 3
- [x] 8.7 Add a `CHANGELOG.md` entry covering the prompt-size reduction, the `astack run-state` wording fix, the scoped resolver permission entries, the new `astack-ops` skill, and the new doctor warning; the CI-pin entry is owned by PR #16
- [x] 8.8 Fresh-worktree check for the spec's "Fresh worktree" scenario: in a fixture install, commit the installed skills, create a second checkout with `git worktree add`, and confirm every enabled host still discovers each skill exactly once with `setup check` and `scripts/doctor.sh` reporting no drift
- [x] 8.9 Update `docs/SKILLS.md` (and `docs/RUN_STATE.md` if needed) so skill bodies are documented as the home for procedure detail previously inlined in the resolver, and `astack-ops` is documented as the CLI map
- [x] 8.10 Confirm the change's file list omits `scripts/run-state.py` and every other gate-enforcing code path — the checkable form of the spec's "Enforcement code is untouched" scenario — so gate behavior is unchanged by construction
