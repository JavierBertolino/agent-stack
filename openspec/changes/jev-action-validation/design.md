## Context

The existing Jev caller accepts TypeSafe `choice` questions and forwards
their criteria unchanged. The existing web/mobile builders already separate
selection from the functional/view/business evaluation set. The missing part
is a concrete decision boundary between a response and a later MCP call.

Official TypeSafe references reviewed for this design:

- https://docs.typesafe.ai/api.md
- https://docs.typesafe.ai/primitives/choice.md
- https://docs.typesafe.ai/confidence.md
- https://docs.typesafe.ai/concepts/state.md
- https://docs.typesafe.ai/agent-skill.md

The implementation adapts those concepts to Agent Stack. It does not copy
product-specific paths, rules, routes, fixtures, or helper code.

## Goals / Non-Goals

**Goals:**

- Make the Jev Choice response pass an executable, fail-closed validation
  step before an agent uses an MCP tool.
- Keep recommendations bounded to candidate ids authored from fresh
  observations; preserve separate local authorization and precondition data.
- Ship one neutral skill for both QA agents and install all referenced files
  through Agent Stack's canonical-source workflow.
- Preserve one action/one observation, deterministic values, privacy rules,
  selection/evaluation separation, and current provider transport.

**Non-Goals:**

- Jev does not control browser/device MCPs, provide action arguments, grant
  authorization, or execute actions.
- The validator is not an MCP middleware or host-enforced sandbox; the role
  contract requires the agent to run it before a tool call.
- No second transport, new TypeSafe question type, provider, credential,
  screenshot upload, or product-specific policy.
- No changes to the evaluation question set or evaluation confidence rules.

## Decisions

### D1 — Reuse the existing transport and TypeSafe Choice

Selection remains the `next_action` Choice sent through the existing
`ask-jev.ts`. The public criteria map contains only candidate descriptions and
possible effects. Authorization and preconditions stay in the agent's local
candidate records. This avoids leaking permissions or executable arguments
and does not create a second caller.

### D2 — One shared host-neutral gate

`.agent-stack/resources/jev/action-selection.ts` owns candidate validation,
question construction, and response validation for both QA surfaces. The
stdin/stdout `validate-action-selection.ts` adapter is installed at
`scripts/jev/`. It receives the exact raw response, candidate records,
observation sent to Jev, and a fresh observation. It returns `execute`,
`inspect_more`, `stop`, `reinspect`, or `reject`; only `execute` includes an
action candidate id. It never invokes a tool.

Candidate ids are bounded opaque snake_case identifiers. The set contains
2–15 options and always includes `inspect_more`. Action candidates and `stop`
require explicit authorization plus non-empty JSON Pointer preconditions;
unauthorized actions are refused before forming a Jev question.

### D3 — Validate the entire answer, not only its selected id

The gate requires a Choice answer under the expected question id, a selected
id in the current candidate set, probabilities for exactly every offered id
that sum to 1 within 0.01 tolerance, finite values in `[0,1]`, and finite
confidence in `[0,1]`. Confidence below the existing fixed `0.75` action
floor returns `inspect_more`. This gate cannot be lowered through request
data.

Submitted and current observations must match, then the selected candidate's
preconditions are compared against the fresh observation using RFC 6901 JSON
Pointer traversal and exact JSON values. A changed observation or failed
precondition returns `reinspect`; malformed responses and unknown ids return
`reject`. No such result authorizes an MCP call.

### D4 — Add `typesafe-jev` as an on-demand skill

The skill targets `web-qa` and `mobile-qa`. Role prompts point at it and the
shared validator, but keep only the critical execute/no-execute contract. The
skill contains the API references, request shape, privacy notes, and
evaluation separation. It is registered in the canonical manifest, installer
fallback, upgrade loop, doctor audit, and all enabled host mirrors.

### D5 — Keep neutral source and generated distribution in sync

The two validator files remain canonical under `.agent-stack/resources/jev/`
and are copied missing-only to consuming projects. Skill sources remain under
`.agent-stack/skills/`; `scripts/build-installer.sh` owns embedded skill
fallbacks and `setup.sh`. The QA helper resources are installed for both web
and mobile QA, with tests ensuring standalone and checkout installs match.

## Risks / Trade-offs

- [Agent skips the helper] → both role contracts require the gate before an
  MCP action; tests pin the contract. Host-level enforcement remains outside
  scope and is stated honestly.
- [TypeSafe response shape evolves] → record current official docs, reject
  malformed answers, and test the observed response contract rather than
  guessing or coercing fields.
- [Preconditions are incomplete or too strict] → require observed JSON Pointer
  values, fail closed on missing paths, and rebuild after any state change.
- [More local artifacts enlarge install surface] → use one shared module,
  one CLI adapter, existing transport, source-of-truth install patterns, and
  path/equivalence tests.
