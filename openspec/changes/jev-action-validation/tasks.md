## 1. Neutral Jev skill and installer registration

- [x] 1.1 Add `.agent-stack/skills/typesafe-jev/SKILL.md` using the official
  TypeSafe Choice/confidence contract, neutral Agent Stack boundaries, and no
  product-specific rules or paths. `verification: sh tests/test-skills.sh`
- [x] 1.2 Register the skill in the canonical manifest, installer fallback,
  build marker/list, doctor, upgrade, docs, and host mirror tests.
  `verification: sh tests/test-skills.sh && sh tests/test-render-matrix.sh`
- [x] 1.3 Make both QA role sources load the skill and invoke the shared gate
  before any selected MCP action. Keep selection separate from evaluation.
  `verification: sh tests/test-qa-selection.sh`

## 2. Executable shared gate

- [x] 2.1 Add the common bounded candidate builder and fail-closed answer
  validator under `.agent-stack/resources/jev/`; preserve existing
  `ask-jev.ts` transport. `verification: tests/test-jev.sh`
- [x] 2.2 Install both shared resources under consuming-project `scripts/jev/`
  during init and sync. `verification: sh tests/test-render-matrix.sh`
- [x] 2.3 Validate exact Choice fields, candidate/probability correspondence,
  confidence floor, authorization, observation freshness, and JSON Pointer
  preconditions. `verification: tests/test-jev.sh`
- [x] 2.4 Cover accepted execute/stop/inspect results and rejection or
  reinspection for stale ids, malformed probabilities, low confidence,
  changed state, unmet preconditions, and unauthorized candidates.
  `verification: tests/test-jev.sh`

## 3. Docs and specifications

- [x] 3.1 Update Jev docs and web/mobile resource READMEs with required
  candidate data, local-only authorization/preconditions, validator outcomes,
  and the fact that the gate does not control MCPs.
  `verification: grep -n 'validate-action-selection\|does not execute' docs/jev.md .agent-stack/resources/web-qa/README.md .agent-stack/resources/mobile-qa/README.md`
- [x] 3.2 Add the spec delta for reusable Jev guidance and the required
  executable pre-action gate. `verification: openspec status --change jev-action-validation --json`

## 4. Regenerate and verify

- [x] 4.1 Regenerate embedded skill sources and `setup.sh`; do not edit the
  generated file by hand. `verification: scripts/build-installer.sh && scripts/build-installer.sh --check`
- [x] 4.2 Check POSIX shell syntax and installed-file paths, plus standalone
  equivalence. `verification: sh -n scripts/setup-agent-stack.sh && sh -n setup.sh && sh tests/test-path-integrity.sh && sh tests/test-equivalence.sh`
- [x] 4.3 Run the complete suite, doctor in a fixture project, and public
  safety checks. `verification: T=$(mktemp -d "${TMPDIR:-/tmp}/astack-jev.XXXXXX"); trap 'rm -rf "$T"' EXIT; mkdir -p "$T/home" "$T/config" "$T/project"; env -u TYPESAFE_API_KEY -u AI_GATEWAY_API_KEY -u JEV_GATEWAY_API_KEY HOME="$T/home" XDG_CONFIG_HOME="$T/config" sh tests/run.sh && sh scripts/setup-agent-stack.sh init --root "$T/project" --kit-root "$PWD" --platforms opencode,claude,codex,cursor --mcp none && scripts/doctor.sh --root "$T/project" --kit-root "$PWD" && scripts/check-public-safety.sh --kit-root "$PWD"`
