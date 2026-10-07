# Jev QA

Agent Stack uses TypeSafe Jev as its QA evaluation engine for the
standalone `web-qa` (browser) and `mobile-qa` (Maestro) agents. Jev is
text-only: agents compress checkpoints to text and Jev returns verdicts
across functional, view, and business dimensions.

Business checks are project-agnostic:

- `business_rule_respected` — complies with explicit business constraints.
- `forbidden_side_effects_avoided` — no out-of-scope side effects.
- `state_transition_valid` — follows the allowed workflow and invariants.
- `traceability_present` — actor, action, timestamp, reason, and object
  identifiers for sensitive or auditable actions.

Severity is general: cosmetic polish; confusing but completable; or
blocking the task / risking correctness, permissions, data integrity, or
required auditability.

Jev serves two distinct purposes for the QA agents: it recommends the next
action while navigating, and it evaluates results. Nothing else — Jev never
drives the browser or the device.

## Action selection

`web-qa` and `mobile-qa` ask Jev which candidate action to take, once per
checkpoint. The agent owns the loop:

1. Observe the current page or screen and build a **closed candidate set**
   from that single observation. It always contains `inspect_more`, and
   contains `stop` once the goal is met, blocked, or over budget. Only
   actions whose preconditions can be checked against the current state are
   offered — there is no open-ended option.
2. Give each candidate an **opaque, stable identifier**, a description, and
   its possible effects. Identifiers come from what the agent observed.
3. Send one `choice` question whose `criteria` map is exactly that candidate
   set, together with the observed state and the test goal. Jev returns one
   identifier. The `choice` type is the same one used for the `verdict` and
   `domain` questions, and needs no provider-specific handling: the Vercel
   normalization only rewrites `noul` to `boolean`.

    `buildSelectionQuestion` in `scripts/qa/questions.ts` and
    `buildMobileSelectionQuestion` in `scripts/mobile-qa/questions-mobile.ts`
    construct this question. Candidates also carry an explicit local
    `authorized` result, possible effects, and JSON Pointer preconditions
    whose values were observed in the page/screen. Only descriptions and
    effects are sent to Jev.

4. **Validate before executing.** After receiving Jev's raw response, the
   agent takes a fresh observation and runs
   `scripts/jev/validate-action-selection.ts` with the exact candidates, the
   submitted observation, and the fresh observation. The gate validates the
   selected id, the complete probability map, confidence in `[0,1]` (fixed
   floor `0.75`), explicit local authorization, and every JSON Pointer
   precondition against the fresh observation. Only `status: "execute"` and a
   current `candidateId` may proceed to one MCP action. `inspect_more` means
   inspect; `stop` means finish; `reinspect`, `reject`, low confidence,
   malformed output, or a nonzero exit means do not act — refresh, rebuild, or
   escalate as `UNVERIFIED`.
5. Execute **one action, then observe**, record `{ action, observed }`, and
   refresh the state before asking again. If the page changed under the
   observation, the candidate set is stale and is discarded.

Selection is advisory. The browser MCP or Maestro executes the action; the
validator does not call either MCP and cannot enforce runtime access. Jev
never invents values: ids, amounts, dates, serials, and form fields come from
the application, from fixtures, or from another already-observed source, and
the agent supplies them. No selection request carries credentials, personal
data, screenshots, or sensitive information, and selection never widens the
QA write scope, the test target, or any authorization boundary.

## Evaluation

Jev evaluates each checkpoint and the final result across the functional,
view, and business dimensions. This is a separate call with its own state
(`{ test_goal, expected, governance, page, trace }` for web, and
`{ …, screen, trace, device }` for mobile) and the question set defined in
the question libraries. A selection result is never reported as a verdict.

## Setup

```sh
astack auth jev
```

Routes:

1. **TypeSafe direct** — `TYPESAFE_API_KEY` against
   `https://api.typesafe.ai/v1/systemone`.
2. **Vercel AI Gateway** — `AI_GATEWAY_API_KEY` with Jev model
   `typesafe-ai/jev-latest`. Boolean-style `noul` questions are normalized
   to the evaluation protocol's `boolean` type.
3. **Cloudflare / compatible gateway** — `JEV_GATEWAY_URL`,
   `JEV_GATEWAY_API_KEY`, `JEV_MODEL`. The endpoint must expose a
   compatible Jev/evaluation request contract.
4. **OpenRouter (preview)** — exposed but without a verified
   System One-compatible transport; the CLI refuses it with guidance
   instead of shipping a fake compatibility layer.

Credentials are stored user-level (`~/.config/astack/env`, mode 600) and
are never printed, logged, or committed. Reconfigure any time with
`astack auth jev`; validate without storing with
`astack auth jev --validate-only`.

QA agents that require Jev report:

```text
Jev is not configured.

Run:

  astack auth jev
```

## On-demand typed questions

Use `astack jev ask` to send an ad hoc System One request. The JSON request
accepts every TypeSafe question type (`noul`, `choice`, and `score`) in one
batch. Question criteria are passed through unchanged, and the structured
response is written to stdout. Choice criteria are an option map; score
criteria are an ordered list of at least two levels.

```sh
cat <<'JSON' | astack jev ask --request -
{
  "state": {"change": "...", "evidence": "..."},
  "questions": {
    "safe": {
      "type": "noul",
      "instructions": "Does the change preserve the stated invariant?"
    },
    "category": {
      "type": "choice",
      "instructions": "Which area is primarily affected?",
      "criteria": {"data": "Data behavior", "interface": "User interface"}
    },
    "risk": {
      "type": "score",
      "instructions": "How serious is the risk?",
      "criteria": ["Low", "Moderate", "High"]
    }
  }
}
JSON
```

The request can also be read from a file with `astack jev ask --request
request.json`. The model can be selected with `--model`; otherwise the
request model, `JEV_MODEL`, or `jev-latest` is used. The CLI uses provider
routing from `.agent-stack/config.conf` and user credentials from
`~/.config/astack/env` (or the legacy `~/.config/agent-stack/env`); exported
environment variables take precedence. Node.js 22.6+ is required.
