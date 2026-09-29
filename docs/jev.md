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
