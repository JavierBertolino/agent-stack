# web-qa resources

Companion scripts for the standalone `web-qa` agent. Copied to the consuming
project as `scripts/qa/` by `setup-agent-stack.sh` (`init`/`sync` create
missing files only; existing project files are preserved).

- `ask-jev.ts` — zero-dependency Jev caller (Node.js 22.6+). Credentials come
  from exported environment variables or the user-level Agent Stack env
  file, never from command-line arguments. Supports every Jev
  provider configured with `astack auth jev`:
  - `typesafe` (default): `TYPESAFE_API_KEY`
  - `vercel`: `AI_GATEWAY_API_KEY` (Jev model `typesafe-ai/jev-latest`;
    boolean-style `noul` questions are normalized to the Vercel evaluation
    protocol's `boolean` type)
  - `gateway`: `JEV_GATEWAY_URL` + `JEV_GATEWAY_API_KEY` + `JEV_MODEL`
    (the endpoint must expose a Jev/evaluation request contract compatible
    with the System One payload)
  - `openrouter`: preview only — exits with setup guidance until its
    System One-compatible transport is verified
- `questions.ts` — typed atomic question library (functional / view /
  business + verdict/domain/severity). Business checks are
  project-agnostic (business rules, side effects, state transitions,
  traceability). Import it when building custom callers; `ask-jev.ts`
  embeds the same defaults so `--questions` can be omitted.
- `scripts/jev/action-selection.ts` (installed from the shared Jev resources)
  builds bounded selection questions and validates Jev's recommendation;
  `scripts/jev/validate-action-selection.ts` is its stdin/stdout gate. They
  do not execute browser or device actions.

Run:

```sh
export TYPESAFE_API_KEY=...   # or: astack auth jev
node --experimental-strip-types scripts/qa/ask-jev.ts \
  --state /tmp/webqa-state.json [--dims functional,view,business]
```

For a generic `noul`, `choice`, or `score` batch, use
`astack jev ask --request request.json` or pipe JSON through
`astack jev ask --request -`. The request has `state` and a `questions`
object; each question's `type`, `instructions`, and `criteria` are sent to
System One without replacing question types.

When Jev is not configured, the helper exits with:

```text
Jev is not configured.

Run:

  astack auth jev
```

State shape: `{ test_goal, expected, governance, page, trace }` where
`page = { url, title, visible_copy, aria_truncated, console_errors }`.
Jev is text-only — never send screenshots; the agent compresses snapshots
to text first.

## Action selection

The agent also asks Jev to recommend the next action, separately from
evaluation. `buildSelectionQuestion(candidates)` returns a single `choice`
question whose `criteria` map is exactly the candidate set. Each candidate
has an opaque stable `id`, a `description`, `effects`, an explicit local
`authorized` result, and a JSON Pointer `preconditions` map of values observed
in the current page. Keep authorization and preconditions out of the request:
the question only sends descriptions and possible effects. `inspect_more` is
always included; add `stop` when the goal is met, blocked, or over budget.

```ts
import { buildSelectionQuestion, INSPECT_MORE } from "./questions.ts";

const question = buildSelectionQuestion([
  { id: "open_task_row", description: "Open the visible task row", effects: "Loads its details", authorized: true, preconditions: { "/page/visible_copy": "Tasks" } },
  { id: INSPECT_MORE, description: "Re-read the page", effects: "No state change", authorized: true, preconditions: {} },
]);
```

After the Jev response, re-observe and pass the raw response, candidates,
submitted observation, and fresh observation to the installed validator. Only
`status: "execute"` with the current candidate id permits the agent to call
the browser MCP once. `inspect_more` means inspect; `stop` means finish;
`reinspect` or `reject` means do not act. The gate validates the option id,
complete probability map, fixed confidence floor (0.75), explicit
authorization, fresh observation, and all candidate preconditions. It is not
an MCP controller and cannot grant permission. Reuse `ask-jev.ts` as the
only transport; it forwards `choice` unchanged.
