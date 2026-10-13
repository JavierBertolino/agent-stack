## Why

`web-qa` and `mobile-qa` currently ask Jev only about outcomes: the agent
drives the browser or device entirely on its own and, at each checkpoint,
compresses what it observed into text so Jev can judge it. Nothing in that
loop asks Jev where to go next, so route selection rests on the agent's own
unaudited read of a flat accessibility tree — exactly the class of judgment
the kit already delegates to Jev for verdicts. Jev already answers `choice`
questions (`.agent-stack/resources/web-qa/ask-jev.ts` validates and forwards
them, `tests/test-jev.mjs` asserts the transport), and both role prompts
already state the guardrail "Jev never picks browser actions". This change
uses the capability that already ships: Jev recommends among a bounded set of
candidates the agent proposes, and the agent — not Jev — stays in control of
the flow.

## What Changes

- Add an action-selection step to both QA agents: at each checkpoint the
  agent observes the current page/screen, builds a closed set of candidate
  actions (always including `inspect_more` and, where the goal is reached or
  blocked, `stop`), and asks Jev one `choice` question over those
  candidates. Each option carries an opaque, stable identifier, a plain
  description, and its possible effects.
- Keep Jev advisory. The agent validates the returned option before
  executing anything: the option must still exist in the current candidate
  set, its preconditions must match the observed state, it must be authorized
  under the existing authorization rules, and its confidence must clear the
  existing gate. Browser or Maestro execution stays with the MCP tools, and
  the one-action/one-observation cycle is preserved: the state is refreshed
  before Jev is consulted again.
- Add a fail-closed path: when the page changed under the observation, when
  no candidate set can be built, or when confidence is low, the agent
  inspects again, prefers `inspect_more`, or escalates — it does not execute a
  suggested action.
- Keep the value rule explicit: Jev never invents values. IDs, amounts,
  dates, serials, and form fields come from the application, from fixtures, or
  from deterministic sources, and the agent fills them.
- Separate selection from evaluation in both roles: Jev's checkpoint and
  final verdicts across functional, view, and business dimensions continue
  unchanged and stay a distinct concern from the recommendation call.
- Preserve every existing boundary: QA write scope, authorization rules,
  device/browser targeting, and the rule that credentials, personal data,
  screenshots, and sensitive information are never sent to Jev.
- Update `docs/jev.md` and the two resource READMEs to describe the selection
  call and its validation gate. The existing transport is reused; no new
  transport, provider, or question type is added.

No breaking change. No new credential, provider, dependency, or question
type. The shipped role contract changes only in that Jev is now consulted for
a recommendation inside the existing loop; the agent's authority, write
boundary, and final verdict composition are unchanged.

## Capabilities

### New Capabilities

- `jev-action-selection`: the QA agents ask Jev to recommend the next action
  from a bounded, agent-authored candidate set at each checkpoint, validate
  that recommendation against the observed state before acting, and keep
  action selection separate from Jev's existing checkpoint and final
  evaluation.

### Modified Capabilities

<!-- No existing specs in openspec/specs/; this capability is new. -->

## Impact

- `.agent-stack/roles/web-qa.md` and `.agent-stack/roles/mobile-qa.md`:
  replace the "Jev never picks browser/device actions" line with the
  advisory-selection contract, its validation gate, the fail-closed path, and
  the value-source rule. Both are mirrored into
  `scripts/setup-agent-stack.sh`'s `write_role_source` heredocs and the
  generated `setup.sh`.
- `.agent-stack/resources/web-qa/README.md` and
  `.agent-stack/resources/mobile-qa/README.md`: document the selection
  request and the state fields it uses. No helper code change is expected —
  `ask-jev.ts` already supports `choice`.
- `docs/jev.md`: add the action-selection section and keep it distinct from
  the typed-question and evaluation sections.
- Tests: extend `tests/test-jev.mjs` (or add a focused test wired into
  `tests/run.sh`) covering bounded candidate transport, validation of the
  returned option against current state, and rejection of low-confidence,
  stale, or invalid answers.
- Consuming projects receive the change through `astack upgrade`; the
  installed file layout and `astack` command surface are unchanged.