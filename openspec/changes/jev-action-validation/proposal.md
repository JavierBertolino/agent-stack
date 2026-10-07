## Why

The archived `jev-action-selection` change introduced advisory Choice
recommendations, but its pre-execution checks were primarily role prose. A
stale, malformed, unauthorized, or low-confidence answer could still be
followed if an agent skipped or misapplied that prose. The TypeSafe AI skill
offers useful typed-question and confidence patterns, but Agent Stack needs a
neutral procedure and a local executable gate rather than a direct copy of
product-specific tools or rules.

## What Changes

- Add a reusable `typesafe-jev` skill for `web-qa` and `mobile-qa`, covering
  the official Choice response shape, bounded recommendations, privacy,
  deterministic values, and separation of selection from evaluation.
- Add a shared candidate/question builder and a fail-closed validator for
  Jev Choice responses. Validate the selected id, full probability map,
  confidence threshold, explicit local authorization, current observation,
  and JSON Pointer preconditions.
- Keep `ask-jev.ts` as the only transport. The gate validates recommendations
  but never controls or invokes a browser/device MCP.
- Install the helper resources, register and mirror the skill, update QA role
  contracts and documentation, and test both the executable gate and install
  paths.

No credentials, host-specific paths, product data, or additional providers
are introduced. QA evaluation questions remain separate and unchanged.

## Capabilities

### Modified Capabilities

- `jev-action-selection`: define executable validation as the required
  fail-closed gate before the agent executes any recommended browser/device
  action.

### New Capabilities

- `typesafe-jev-skill`: ship a neutral reusable Jev skill and make it
  discoverable to both QA roles.

## Impact

- Sources: `.agent-stack/skills/typesafe-jev/`, `.agent-stack/resources/jev/`,
  QA question libraries, QA role contracts, and Jev resource documentation.
- Install/upgrade: skill manifest and mirrors, installer fallback sources,
  `scripts/jev/` resource installation, and three-way upgrade registration.
- Tests: behavior-level validation cases, role contract assertions, install
  matrix, standalone equivalence, skill registry, and upgrade checks.
- Generated output: `scripts/build-installer.sh` regenerates
  `scripts/setup-agent-stack.sh` skill source and `setup.sh`.
