## ADDED Requirements

### Requirement: QA agents validate Jev recommendations through the shared gate

The `web-qa` and `mobile-qa` agents SHALL use the installed neutral
`typesafe-jev` skill and SHALL run the shared action-selection validator after
each Jev selection and before any browser or device MCP action. Only a
validator result with `status: "execute"` and a candidate id in the current
candidate set SHALL permit one MCP action. The validator SHALL NOT invoke an
MCP, execute an action, or grant authorization.

#### Scenario: Valid recommendation passes
- **WHEN** Jev returns a well-formed Choice whose id is in the current set,
  probabilities cover the exact candidate set and sum to 1, confidence meets
  the fixed `0.75` floor, local authorization is true, and observed
  preconditions match a fresh observation
- **THEN** the gate returns `status: "execute"` with that candidate id, and
  the agent may execute exactly one action through its existing MCP

#### Scenario: Unknown identifier or malformed probability map
- **WHEN** Jev returns an id outside the candidate set or the probability map
  is missing, has extra ids, contains invalid values, or does not sum to 1
- **THEN** the gate rejects the answer and the agent SHALL NOT make an MCP
  action call from that recommendation

#### Scenario: Low confidence
- **WHEN** a syntactically valid answer has confidence below the fixed action
  floor (`0.75`)
- **THEN** the gate returns `inspect_more` and no mutating action is executed

#### Scenario: Observation changes or precondition fails
- **WHEN** the fresh observation differs from the submitted observation, or a
  selected candidate's JSON Pointer precondition is absent or does not match
- **THEN** the gate returns `reinspect`; the agent discards the old candidate
  set and does not execute the recommendation

#### Scenario: Candidate is unauthorized
- **WHEN** a candidate is marked unauthorized or lacks explicit local
  authorization and observable preconditions
- **THEN** it cannot be offered as an executable candidate, and no Jev
  recommendation can make it authorized

#### Scenario: Jev selects an escape option
- **WHEN** the selected id is `inspect_more` or an authorized `stop` whose
  preconditions match
- **THEN** the gate returns the corresponding non-execution status, and the
  agent inspects or ends the flow without treating it as a verdict
