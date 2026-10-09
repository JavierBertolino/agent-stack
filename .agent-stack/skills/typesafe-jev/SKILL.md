---
name: typesafe-jev
description: Use TypeSafe Jev safely in Agent Stack web and mobile QA: build bounded Choice decisions, validate recommendations, and keep evaluation separate from actions.
metadata:
  version: "1.0"
  consumer: web-qa, mobile-qa
  stage: qa
---

# TypeSafe Jev for QA

Use this skill before making Jev selection or evaluation calls. Jev returns
typed judgments; the QA agent owns the workflow, verifies evidence, and calls
the browser MCP or Maestro. **Jev never executes an action, grants
authorization, or supplies a value.**

## Source of truth

The installed `scripts/qa/ask-jev.ts` is the transport and provider-routing
authority. Reuse it; do not add a second TypeSafe client, hardcode a provider,
or move credentials into project files. When changing the integration or
depending on a response detail, check the current TypeSafe docs:

- [System One API](https://docs.typesafe.ai/api.md)
- [Choice](https://docs.typesafe.ai/primitives/choice.md)
- [Confidence](https://docs.typesafe.ai/confidence.md)
- [State](https://docs.typesafe.ai/concepts/state.md)
- [TypeSafe agent skill](https://docs.typesafe.ai/agent-skill.md)

Choice responses contain `type: "choice"`, `choice`, `probabilities` for the
options, and `confidence` from 0 to 1. Do not invent response properties. A
question id is chosen by the caller; its answer is returned under that id.
The Vercel adapter normalizes `noul` only; `choice` remains unchanged.

## Select one next action

Selection is separate from evaluation and happens at a checkpoint:

1. Observe the current page/screen. Build a closed candidate set from that
   observation, with `inspect_more` always present and `stop` only when the
   goal is met, blocked, or the test budget is exhausted. Keep the set small
   (2–15); do not include an open-ended option.
2. Give every candidate a stable opaque `id`, clear `description`, possible
   `effects`, local `authorized` result, and JSON-Pointer `preconditions`
   whose expected values come from the observed state. Do not include
   unauthorized candidates. Never put form values or executable tool
   arguments in the Jev option description.
3. Use `buildSelectionQuestion` from `scripts/qa/questions.ts` or
   `buildMobileSelectionQuestion` from
   `scripts/mobile-qa/questions-mobile.ts`. Each builds one `choice`
   question named `next_action`; only id, description, and possible effects
   are sent to Jev. The state should be a redacted `{ test_goal, observation
   }` summary. Do not send screenshots.
4. Call the existing helper with a typed request, for example:

   ```sh
   node --experimental-strip-types scripts/qa/ask-jev.ts --request /tmp/jev-selection-request.json
   ```

   Keep transient request/response files outside the repository and remove
   them after use. They must not contain secrets or sensitive data.
5. Re-observe before acting. Feed the raw Jev response, the exact candidate
   records, the submitted observation, and the fresh observation to
   `scripts/jev/validate-action-selection.ts` on stdin. Its input shape is:

   ```json
   {
     "question_id": "next_action",
     "response": { "answers": { "next_action": {
       "type": "choice", "choice": "open_record", "confidence": 0.91,
       "probabilities": { "open_record": 0.91, "inspect_more": 0.09 }
     } } },
     "candidates": [
       { "id": "open_record", "description": "Open the visible record",
         "effects": "Shows its details", "authorized": true,
         "preconditions": { "/page/visible_copy": "Records" } },
       { "id": "inspect_more", "description": "Read the page again",
         "effects": "No state change", "authorized": true,
         "preconditions": {} }
     ],
     "submitted_observation": { "page": { "visible_copy": "Records" } },
     "current_observation": { "page": { "visible_copy": "Records" } }
   }
   ```

   Only a JSON result with `status: "execute"` and a `candidateId` matching
   the current set can proceed to the MCP. `status: "inspect_more"` means
   re-read the page/screen without a mutating action; `status: "stop"` means
   end the QA flow. `reinspect`, `reject`, malformed output, nonzero exit,
   or missing output means **do not act**; refresh, rebuild candidates, or
   escalate as `UNVERIFIED`.
6. The validator compares the submitted and fresh observations, checks the
   selected id, verifies the complete probability map and confidence, checks
   `authorized`, and matches every candidate JSON Pointer precondition
   against the current observation. Its action confidence floor is fixed at
   `0.75`, matching the existing QA contract. Do not lower or override it.
7. Execute at most the single validated action through the browser MCP or
   Maestro. Record `{ action, observed }`, then take a new observation before
   asking Jev again. Never reuse an earlier selection after a page/screen
   change. The validator is a gate for the agent's next tool call; it is not
   an MCP controller and cannot grant access beyond existing permissions.

## Values and data boundaries

Jev selects among candidates; it does not generate record ids, amounts,
dates, serials, or form values. The agent obtains and enters those values
from the application, fixtures, or another deterministic source. Send Jev
only the minimum redacted text needed to make the judgment — never API keys,
session credentials, personal data, screenshots, or sensitive information.
The question builder is not a redactor; review the state and candidate
descriptions before sending.

## Evaluate results separately

After each action/observation and at the final checkpoint, use the existing
web or mobile evaluation library and its functional, view, and business
questions. Selection answers are not verdicts. Do not combine
`next_action` into the evaluation batch: the evaluation call has its own
state and produces PASS/BLOCKING/NIT/UNVERIFIED. Preserve the existing
confidence handling for evaluation answers.

If Jev is unavailable or an answer is invalid, do not fabricate a decision
or verdict. Report the limitation and mark affected criteria `UNVERIFIED`.
