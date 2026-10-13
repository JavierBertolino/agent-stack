# mobile-qa resources

Companion scripts for the standalone `mobile-qa` agent (Maestro MCP +
device/emulator). Copied to the consuming project as `scripts/mobile-qa/`
by `setup-agent-stack.sh` (`init`/`sync` create missing files only).

- `questions-mobile.ts` — typed atomic question library (functional / view /
  business + verdict/domain/severity) for use with the shared Jev caller at
  `scripts/qa/ask-jev.ts`. Business checks are project-agnostic (business
  rules, side effects, state transitions, traceability). Pass `--questions`
  with a JSON file rendered from `buildMobileQuestions()`, or inline the
   state below.
- The shared `scripts/jev/action-selection.ts` builds bounded selection
  questions and validates Jev recommendations. The installed
  `scripts/jev/validate-action-selection.ts` reads JSON from stdin and returns
  a fail-closed decision; it does not execute Maestro actions.

The shared Jev caller also powers `astack jev ask`; its generic JSON request
supports `noul`, `choice`, and `score` questions for either browser or mobile
evidence. Mobile QA continues to use its own question library below.

Jev credentials come from exported environment variables or the user-level
Agent Stack env file — configure them once with:

```sh
astack auth jev
```

When Jev is not configured, the shared caller exits with setup instructions
instead of judging; mark affected criteria `UNVERIFIED` until then.

## Action selection

Alongside evaluation, the agent asks Jev to recommend the next device action.
`buildMobileSelectionQuestion(candidates)` returns a single `choice` question
whose `criteria` map is exactly the candidate set, so Jev can only recommend
one of the options the agent authored. Each candidate carries an opaque stable
`id`, a `description`, `effects`, an explicit local `authorized` result, and
JSON Pointer `preconditions` whose expected values come from the observed
screen. Authorization and preconditions remain local; only descriptions and
possible effects are sent to Jev. `MOBILE_INSPECT_MORE` is always included;
include `MOBILE_STOP` when the goal is met, blocked, or over budget.

```ts
import { buildMobileSelectionQuestion, MOBILE_INSPECT_MORE }
  from "./questions-mobile.ts";

const question = buildMobileSelectionQuestion([
  { id: "tap_confirmar", description: "Tap the visible Confirmar button", effects: "Dismisses the dialog", authorized: true, preconditions: { "/screen/visible_copy": "Confirmar" } },
  { id: MOBILE_INSPECT_MORE, description: "Re-read the screen", effects: "No state change", authorized: true, preconditions: {} },
]);
```

After Jev responds, re-inspect and pass the raw response, candidates, submitted
observation, and fresh observation to the validator. Only `status: "execute"`
with the current candidate id permits one Maestro action. `inspect_more` means
inspect; `stop` means finish; `reinspect` or `reject` means do not act. The
gate validates the option id, complete probability map, fixed 0.75 confidence
floor, authorization, observation freshness, and all candidate
preconditions. It is not a Maestro controller and cannot grant permission.
Reuse `ask-jev.ts` as the only transport; it forwards `choice` unchanged.

State shape for the shared caller:

```json
{
  "test_goal": "Cerrar una tarea desde la lista",
  "expected": "La tarea pasa a cerrada con confirmación visible",
  "governance": { "P02": "...", "P05": "...", "copy_rule": "..." },
  "screen": {
    "hierarchy_truncated": "<inspect_screen compact JSON>",
    "visible_copy": "text on screen",
    "focused_element": "resource-id or label",
    "console_or_flow_errors": "maestro run output tail"
  },
  "trace": [{ "action": "tap Cerrar", "observed": "dialog Confirmar" }],
  "device": { "serial": "...", "model": "...", "os": "...", "build": "..." }
}
```

Device execution itself goes through the Maestro MCP tools (`list_devices`,
`inspect_screen`, `run`, `take_screenshot`); no local runner script is
needed. Requires Maestro CLI + Java on PATH and a booted emulator or
connected device with the target app installed.
