## Context

Current state of the QA loop, from the shipped sources:

- `.agent-stack/roles/web-qa.md` §3 "Drive (code owns the loop)" states
  "You own browser control flow. Jev never picks browser actions", then four
  steps: observe, act deterministically (one action, one observation, record
  `{ action, observed }`), serialize the checkpoint, re-check persistence.
  §4 "Judge (Jev supplies verdicts)" is a separate section that sends one
  `system_one` call per checkpoint with the functional / view / business
  `Noul` set plus `verdict` (choice), `domain` (choice), and `severity`
  (score).
- `.agent-stack/roles/mobile-qa.md` is the same shape for Maestro
  (`inspect_screen`, inline `{ yaml }` flows, `trace`, `device`).
- `.agent-stack/resources/web-qa/ask-jev.ts` already transports `choice`:
  `validateRequest` accepts `noul | choice | score`, requires a non-empty
  option map for `choice`, and `main()` forwards `{ state, model, questions }`
  to the provider endpoint unchanged. `buildDefaultQuestions` already emits
  two `choice` questions (`verdict`, `domain`). `tests/test-jev.mjs` asserts
  a `choice` question and its `state` arrive at the endpoint verbatim.
  So the transport needed for action selection already exists.
- The question libraries (`questions.ts`, `questions-mobile.ts`) are typed
  builders returning `noul` / `choice` / `score` definitions with
  `instructions` + optional `criteria`. A candidate set maps cleanly onto
  `choice` criteria (opaque id → description + effects), which is exactly the
  shape `validateRequest` already requires.
- Nothing today validates a Jev answer against a re-observed state, because
  nothing today acts on a Jev answer. The `confidence < 0.75` gate in both
  roles currently only turns an evaluation answer into `UNVERIFIED`.
- The Jev response shape is opaque to the helper: it prints the endpoint's
  JSON. Nothing in the kit models `answers.<name>.choice` or the
  `confidence` field the roles already reference, so there is no installed
  code that turns a Jev answer into a decision.

Constraints that shape this design:

- Neutral sources are authored once under `.agent-stack/`; `setup.sh` is
  generated and must be rebuilt with `scripts/build-installer.sh`.
- Prompt budgets in `tests/test-prompt-budgets.sh` are enforced: neutral
  roles ≤ 7,000 B / 400 lines (resolver 13,800 B), rendered agents
  ≤ 14,900 B. `mobile-qa.md` is already **6,180 B against the 7,000 B
  budget — only ~820 B of headroom** — while `web-qa.md` has ~2,253 B. The
  selection contract must therefore be compact, or `mobile-qa.md` must shed
  equivalent bytes from what it replaces.
- `tests/test-path-integrity.sh` fails when a shipped role names a
  backticked, directory-qualified path that a fresh install does not create.
  Any new path named by a role (for example `scripts/qa/`) must be installed
  by `ensure_webqa_resources` / `ensure_mobileqa_resources`.
- Existing authorization, QA write scope (`reports/qa/*.md` plus scratch
  flows), and data rules stay in force; credentials, personal data,
  screenshots, and sensitive information must not reach Jev.

## Goals / Non-Goals

**Goals:**

- Have Jev recommend the next action at each checkpoint from a bounded,
  agent-authored candidate set, in both `web-qa` and `mobile-qa`.
- Keep Jev advisory: the agent validates every recommendation against the
  observed state before acting, and never lets a recommendation expand its
  own authority.
- Keep selection strictly separate from Jev's existing functional / view /
  business evaluation, which must keep working unchanged.
- Make the fail-closed paths explicit and testable: page changed, no
  candidate set buildable, low confidence, unknown or stale option id.
- Ship the smallest possible change: no new transport, provider, question
  type, credential, or dependency.

**Non-Goals:**

- Jev never becomes the browser or device controller. It selects among
  options the agent presents; the MCP tools execute.
- No autonomous multi-step planning, no loop driving, no self-correcting
  replay, and no change to the one-action/one-observation cadence.
- No new Jev question types beyond `choice`, no scripted candidate
  generator, and no attempt to formalize Jev's response schema beyond what
  the roles already assume.
- No change to handoff/report/run-state schemas, the `design-qa` role, the
  four delivery roles, or any authorization or write boundary.
- Behavioral evaluation of whether selection improves QA outcomes: out of
  scope, same reason as in `reduce-agent-token-usage`. The checkable
  stand-in is contract text plus transport tests.

## Decisions

**D1 — Reuse `choice` through the existing transport; add no new mode.**
The selection call is a `choice` question named `next_action` whose
`criteria` is the candidate map: opaque stable id → "what it does; possible
effects". `ask-jev.ts` already accepts this (`validateRequest` requires a
non-empty object of criteria for `choice`) and forwards it unchanged, so no
transport work is needed. Alternative considered: a dedicated `--select`
CLI flag or a second request path. Rejected — it duplicates the existing
request shape and adds a code path the current transport already covers.

**D2 — Identifiers are opaque and stable, and are the only thing Jev may
return.** Each candidate gets a stable slug the agent assigns from the
observed element (for example `open_task_row`, `confirm_submit`,
`inspect_more`, `stop`), never an invented value. The agent — not Jev —
supplies the concrete argument for any action that needs one (an id, an
amount, a date, a serial, a form value), sourced from the application,
fixtures, or another deterministic source already observed. Alternatives:
(a) let Jev fill form values in the description; rejected, it violates the
existing rule that the agent supplies values. (b) put arguments in the
description and treat them as executable; rejected, that is how stale
recommendations become silent data corruption.

**D3 — Validation is a named gate in the role, executed before the MCP
call, and it is fail-closed.** Before executing a recommended option the
agent must confirm, in order: the returned id exists in the candidate set it
just built; its preconditions still match the current observation; it is
authorized under the existing rules; its confidence clears the gate already
in the roles (`confidence < 0.75` for `choice`). Any failure means no
action: re-inspect, choose `inspect_more`, or escalate to the caller as
`UNVERIFIED`. Alternatives considered: (a) trust Jev and act — rejected,
the page can change between the observation and the answer; (b) re-ask
automatically N times — rejected, it hides a genuine ambiguity and burns
turns, which is the token cost `reduce-agent-token-usage` exists to
remove.

**D4 — Observation freshness is explicit.** The candidate set is built from
one observation, and the state is refreshed after every action before Jev is
consulted again. If the page changed under the observation (unexpected
navigation, dialog, async update), the current candidate set is discarded and
the agent re-inspects. This keeps the existing "one action, one
observation" cadence rather than introducing a plan-then-execute phase.

**D5 — Candidate set is closed and always includes the escape hatches.**
The set is what the agent proposes at this checkpoint — no free-form action
request, no "anything else" option. `inspect_more` is always present;
`stop` is always present once the goal is met, blocked, or the budget for
this checkpoint is exhausted. This bounds both the Jev call and the blast
radius of a bad recommendation. Alternative: a fixed global action menu;
rejected, it would offer actions whose preconditions cannot be checked
against the current page.

**D6 — Selection and evaluation are separate calls with separate state.**
Selection sends the observed page/screen, the goal, and the candidate set.
Evaluation sends the existing `{ test_goal, expected, governance, page,
trace }` (web) / `{ ..., screen, trace, device }` (mobile) state and the
existing functional / view / business questions, unchanged. Two distinct
sections in each role, so a failed or unconfigured selection call can never
be mistaken for an evaluation verdict and vice versa. If Jev is not
configured at all, both stop: selection cannot run and evaluation marks
`UNVERIFIED`, which is the existing behavior.

**D7 — Keep the roles within budget by replacing, not appending.**
`mobile-qa.md` has ~820 B of headroom, so the selection contract is written
to replace the "Jev never picks device actions" line plus the now-redundant
repetition in §4 rather than adding a new section. If a role still exceeds
7,000 B, trim in the same file and record the measured numbers in
`tasks.md` — budgets are not raised for this change.

**D8 — Tests cover transport and contract, not agent behavior.** Extend
`tests/test-jev.mjs` to assert that a `choice` request over a bounded
candidate set is forwarded verbatim (state, id keys, criteria text), and
that a malformed or unsupported request is refused. Add a small installed
validation helper only if the role's gate can be expressed as code rather
than prose; otherwise the gate is asserted by role-text checks. Alternative:
a full simulated agent loop; rejected, it would encode behavior the kit does
not own and would not survive model changes.

## Risks / Trade-offs

- [Jev may recommend a valid-looking but unhelpful action] → bounded
  candidate set (D5) plus the evaluation call still judging the result, so a
  poor route shows up as a poor `verdict`, and `stop` / `inspect_more`
  remain available.
- [Stale recommendation after an async page change] → D3's precondition
  re-check and D4's refresh-every-action rule; failure is fail-closed.
- [Selection adds a Jev call per checkpoint] → cost grows per step; bounded
  by the candidate set and by not re-asking on failure (D3). Acceptable
  because Jev calls are small text requests and the alternative is
  unaudited route choice.
- [Role text grows] → D7; `tests/test-prompt-budgets.sh` fails if a role or
  rendered agent crosses its ceiling.
- [A new path named by a role is not installed] → `tests/test-path-integrity.sh`
  catches it; any named helper must be added to
  `ensure_webqa_resources` / `ensure_mobileqa_resources`.
- [Prose gate drifts from real behavior] → accepted limitation. The gate is
  enforced by the agent, not the host; the tests pin the transport and the
  contract text, not model behavior.