## 1. Transport check (confirm nothing new is needed)

- [x] 1.1 Verified in `.agent-stack/resources/web-qa/ask-jev.ts`: `validateRequest` (line 74) accepts `choice` in the type whitelist (line 89) and requires a non-empty option-map `criteria` (lines 96-97); `main()` forwards `{ state, model: provider.model, questions }` verbatim (line 315). No transport change needed.
- [x] 1.2 Verified: `normalizeQuestionsForVercel` (lines 256-269) rewrites only `type === "noul"` to `boolean`; `choice` takes the `else` branch untouched, so a selection request needs no provider-specific handling on typesafe, vercel, or gateway.
- [x] 1.3 Decision: **add an additive selection builder** to both question libraries — `buildSelectionQuestion` / `buildMobileSelectionQuestion`, plus `CandidateAction` / `MobileCandidateAction` and the `INSPECT_MORE` / `STOP` id constants. Rationale: the candidate map is the security-relevant surface of this change (opaque ids, per-option effects, no duplicates), so it is expressed as typed, testable code rather than prose an agent could vary. The exported evaluation set (`DIMENSIONS`, `buildQuestions`, `MOBILE_DIMENSIONS`, `buildMobileQuestions`) is unchanged; the builder returns a standalone `choice` question the agent sends as its own request, not part of the evaluation batch.

## 2. web-qa role

- [x] 2.1 In `.agent-stack/roles/web-qa.md` §3, replace "You own browser control flow. Jev never picks browser actions." with the advisory contract: the agent owns the loop, Jev recommends among agent-authored candidates
- [x] 2.2 Add the candidate-set rule to §3: built from one observation, always includes `inspect_more`, includes `stop` when the goal is met/blocked/over budget, no unvalidatable or open-ended candidates
- [x] 2.3 Add the option shape rule: opaque stable identifier, description, possible effects, one `choice` question per selection through `scripts/qa/ask-jev.ts`, sent with the observed state and `test_goal`
- [x] 2.4 Add the pre-execution gate as an explicit ordered list: identifier still in the candidate set, preconditions match the observation, authorized under existing rules, confidence at or above the existing `choice` gate; any failure means no execution — re-inspect, `inspect_more`, or escalate `UNVERIFIED`
- [x] 2.5 Add the freshness rule: refresh the observed state after every action before consulting Jev again; discard a stale candidate set when the page changed under the observation
- [x] 2.6 Add the value-source rule: ids, amounts, dates, serials, and form values come from the app, fixtures, or an already-observed deterministic source; the agent supplies them and never invents one
- [x] 2.7 Reword §4 so selection and evaluation read as two distinct calls: selection sends goal + observation + candidates, evaluation keeps the existing `{ test_goal, expected, governance, page, trace }` state and the unchanged functional/view/business question set, and a selection result is never reported as a verdict
- [x] 2.8 Extend §Guardrails: credentials, personal data, screenshots, and sensitive information never enter a selection or evaluation request; the selection cannot widen the QA write scope, the test target, or any authorization boundary
- [x] 2.9 Keep `.agent-stack/roles/web-qa.md` within the `tests/test-prompt-budgets.sh` ceiling by replacing rather than appending. Measured: **6,344 B / 147 lines** against the 7,000 B / 400-line budget (was 4,747 B / 123). No budget change.

## 3. mobile-qa role

- [x] 3.1 Apply the same §3 changes as 2.1–2.6 to `.agent-stack/roles/mobile-qa.md`, using Maestro vocabulary (`inspect_screen`, inline `{ yaml }` flows, `device`, back/gesture behavior) and keeping the existing `run_on_cloud` approval rule
- [x] 3.2 Apply 2.7 to §4 so mobile selection and mobile evaluation stay separate calls, with the existing `{ test_goal, expected, governance, screen, trace, device }` state unchanged for evaluation
- [x] 3.3 Apply 2.8 to §Guardrails, keeping the QA write scope as `reports/qa/*.md` plus scratch flows
- [x] 3.4 Keep `.agent-stack/roles/mobile-qa.md` within budget without raising it. Measured: **6,989 B / 144 lines** against the 7,000 B / 400-line budget (was 6,180 B / 148; net +809 B, ~11 B under the ceiling). Absorbed by replacing, per 3.4: folded the separate `## 0. Prerequisites` section into discovery item 1; collapsed the §2 intake bullet list into prose; removed the duplicated `system_one` framing and the verbatim `Jev is not configured` fenced block from §4 (the helper still prints it; `docs/jev.md` keeps the canonical text); merged the value-source rule into the candidate-set step; trimmed the report-format guidance lines and one guardrail sentence. Budget unchanged.

## 4. Docs

- [x] 4.1 Add an action-selection section to `docs/jev.md` describing the candidate set, the single bounded `choice` call, the advisory-only rule, the pre-execution gate, the fail-closed paths, and the value-source rule; keep it visibly separate from the existing typed-question and evaluation sections
- [x] 4.2 Update `.agent-stack/resources/web-qa/README.md`: document the selection request shape alongside the existing state shape, and confirm no helper change was needed
- [x] 4.3 Update `.agent-stack/resources/mobile-qa/README.md` the same way for the Maestro state shape

## 5. Tests

- [x] 5.1 Extend `tests/test-jev.mjs` with a selection case: a request whose `next_action` is a `choice` over a bounded candidate map is forwarded verbatim, asserting the criteria keys equal the candidate identifiers and that `state` reaches the endpoint unchanged
- [x] 5.2 Add a negative transport case: an empty `criteria` map for the selection `choice` is refused with the existing validation error, so a malformed candidate set cannot reach Jev
- [x] 5.3 Add an identifier-staleness case: a returned identifier absent from the submitted candidate set must not validate, so a stale answer is distinguishable from a valid one. Asserted against the set of submitted ids: a known id matches, `now_dismiss_overlay` and `""` do not, and an unknown id fails even at `confidence 0.99`.
- [x] 5.4 Add `tests/test-qa-selection.sh` (picked up automatically by the `tests/test-*.sh` loop): asserts both roles keep the one-action/one-observation cadence, neither describes Jev as executing actions, the closed candidate set with `inspect_more`/`stop`, the opaque-id and possible-effects rules, the four ordered gate checks plus fail-closed wording, the no-invented-values rule, selection separated from evaluation, and the unchanged evaluation question set (regression guard). Assertions run against whitespace-collapsed role copies so wrapped sentences match. Verified the test is not vacuous by temporarily deleting the gate's confidence and fail-closed sentences — it failed, then passed again after restore.
- [x] 5.5 Confirm `tests/test-path-integrity.sh` passes: no new installed file was introduced (the selection builder is an additive export inside the existing `questions.ts` / `questions-mobile.ts`), so `ensure_webqa_resources` / `ensure_mobileqa_resources` needed no change. Result: 224 installed path candidates resolve.
- [x] 5.6 Confirm the new/updated tests are picked up by the `tests/test-*.sh` loop in `tests/run.sh`: both `tests/test-jev.sh` and `tests/test-qa-selection.sh` ran in the suite.

## 6. Verify and regenerate

- [x] 6.1 Run `sh tests/run.sh`: **12 passed, 1 failed**. The failure is `test-public-release.sh` (init must print the Jev follow-up), and it is pre-existing and environment-dependent: this machine has `~/.config/astack/env`, so `jev_is_configured` is true and init legitimately skips the "not configured yet" hint. Confirmed by stashing all changes and reproducing the same failure on the untouched tree, and by re-running hermetically with a temporary `HOME`/`XDG_CONFIG_HOME` and the three Jev keys unset — **exit 0**.
- [x] 6.2 Run `scripts/doctor.sh`: 1 failure, `FAIL Agent Stack is not initialized in this directory` — the kit's own checkout is not an installed project, so this is expected in the kit source tree. Pre-existing: reproduced identically with all changes stashed. Everything else passes (contracts, OpenSpec config, all 9 skill mirrors consistent, Jev TypeSafe direct, version current). The `governance UX_AGENTS/UI_AGENTS: missing` and unconfigured-integration lines are informational.
- [x] 6.3 Run `scripts/build-installer.sh` to regenerate `setup.sh` from the updated neutral sources (never hand-edited), then `--check`: **"build-installer: outputs are reproducible (no changes)"**, exit 0. `sh -n` passes on both `scripts/setup-agent-stack.sh` and `setup.sh`.
- [x] 6.4 Run `scripts/check-public-safety.sh`: "no private references found", exit 0.
- [x] 6.5 Report changed files, test output, measured role sizes against budget, and limitations.