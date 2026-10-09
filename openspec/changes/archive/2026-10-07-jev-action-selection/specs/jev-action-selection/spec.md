## ADDED Requirements

### Requirement: Candidate actions are authored by the agent from the current observation
At each checkpoint, both the `web-qa` and `mobile-qa` agents SHALL build a
closed set of candidate actions from the current observed page or screen
before consulting Jev. The set SHALL contain `inspect_more` in all cases,
and SHALL contain `stop` whenever the test goal is met, the task is blocked,
or the checkpoint's budget is exhausted. The set SHALL offer only actions
whose preconditions the agent can check against the current observation; no
free-form or open-ended action may be offered.

#### Scenario: Checkpoint with usable candidates
- **WHEN** the agent observes a page where the goal can be advanced
- **THEN** it builds a candidate set containing `inspect_more` and at least
  one goal-advancing candidate, with no option that would act on an element
  it did not observe

#### Scenario: Goal already satisfied
- **WHEN** the observed state shows the goal in `test_goal` completed
- **THEN** the candidate set includes `stop`, and selection is used to
  confirm stopping rather than to open a new path

#### Scenario: No candidate can be validated
- **WHEN** the observation yields no action whose preconditions can be checked
- **THEN** the agent does not ask Jev to select, inspects again or escalates
  the checkpoint as `UNVERIFIED`

### Requirement: Jev is asked to select among the candidates with a single bounded choice question
The agent SHALL send exactly one `choice` question per selection, through the
existing Jev caller, whose criteria are the candidate set. Each option SHALL
carry an opaque, stable identifier assigned by the agent, a clear
description of what the action does, and its possible effects. The selection
request SHALL carry the observed state and the test goal. The existing
transport and question types SHALL be reused; no additional transport or
question type is introduced.

#### Scenario: Selection request is bounded and self-describing
- **WHEN** the agent requests a selection for a candidate set of `n` options
- **THEN** the request contains one `choice` question whose criteria map has
  exactly those `n` opaque identifiers, each mapped to a description and its
  possible effects, alongside the observed state

#### Scenario: Opaque identifiers stay stable
- **WHEN** the agent re-observes an equivalent page and rebuilds the
  candidate set
- **THEN** an identifier for the same action is the same opaque token, so a
  previously observed identifier can be recognized as stale or unchanged

### Requirement: Jev recommends only; the agent validates before executing
Jev SHALL return a recommended option identifier and SHALL NOT drive the
browser or device. Before executing a recommended option, the agent SHALL
verify that the returned identifier still exists in the current candidate set,
that the option's preconditions match the current observation, that the option
is authorized under the existing authorization and QA-permission rules, and
that the recommendation's confidence clears the gate the roles already apply
to `choice` answers. Only the browser MCP or Maestro SHALL execute the action.
If any check fails, the agent SHALL NOT execute the action and SHALL inspect
again, select `inspect_more`, or escalate as `UNVERIFIED`.

#### Scenario: Valid recommendation is executed by the MCP
- **WHEN** Jev returns an identifier that is in the current candidate set,
  whose preconditions still match the observation, which is authorized, and
  whose confidence is at or above the gate
- **THEN** the agent executes exactly that one action through the browser MCP
  or Maestro, records `{ action, observed }`, and refreshes the state before
  consulting Jev again

#### Scenario: Returned identifier is not in the candidate set
- **WHEN** Jev returns an identifier the agent cannot match to a current
  candidate
- **THEN** no action is executed; the agent re-inspects, chooses
  `inspect_more`, or escalates as `UNVERIFIED`

#### Scenario: Preconditions no longer hold
- **WHEN** the selected option's target is no longer present or its
  preconditions no longer match the current observation
- **THEN** no action is executed and the agent re-inspects or escalates

#### Scenario: Option is not authorized
- **WHEN** the selected option would act outside the existing authorization,
  target, or QA-permission boundaries
- **THEN** it is not executed regardless of Jev's recommendation, and the
  deviation is reported

#### Scenario: Low-confidence recommendation
- **WHEN** the recommendation's confidence falls below the gate the roles
  already apply to `choice` answers
- **THEN** no action is executed; the agent captures a fresh observation and
  prefers `inspect_more` or escalates as `UNVERIFIED`

### Requirement: Observation freshness and one-action cadence are preserved
The candidate set SHALL be built from a single observation, and the observed
state SHALL be refreshed after every executed action before Jev is consulted
again. The agent SHALL keep the one-action, one-observation cadence and
SHALL record each executed action and what was observed. If the page or
screen changed under the observation that produced the candidate set, the
agent SHALL discard the stale candidate set and re-inspect rather than
execute.

#### Scenario: Page changes under the observation
- **WHEN** the state differs from the observation the candidate set was built
  from
- **THEN** the candidate set is discarded, no action is executed, and the
  agent re-inspects before building a new set

#### Scenario: State refresh between selections
- **WHEN** one action has been executed and observed
- **THEN** the refreshed state is what a subsequent selection request is
  built from, never the previous checkpoint's state

### Requirement: Jev never supplies values
Identifiers, amounts, dates, device serials, and form field values SHALL come
from the application, from fixtures, or from another deterministic source the
agent already observed. Jev SHALL NOT invent, guess, or generate such values,
and a candidate's description SHALL NOT embed a value the agent did not
source. The agent fills every such value itself when executing the action.

#### Scenario: Action needs a concrete identifier
- **WHEN** a selected candidate targets a specific record and the identifier
  is observable in the application
- **THEN** the agent supplies the observed identifier and the candidate
  description names no other identifier

#### Scenario: Action needs a value not yet observed
- **WHEN** a selected action requires a value absent from the application,
  fixtures, and prior observations
- **THEN** the action is not executed with an invented value; the agent
  obtains it from a deterministic source or escalates as `UNVERIFIED`

### Requirement: Selection stays separate from Jev evaluation
Jev SHALL continue to evaluate each checkpoint and the final result across
the functional, view, and business dimensions, with the existing question set
and confidence gates unchanged. Selection SHALL be a distinct call with its
own state, and its result SHALL NOT be reported as an evaluation verdict. If
Jev is not configured, selection SHALL NOT run and evaluation SHALL mark the
affected criteria `UNVERIFIED` as it does today.

#### Scenario: Evaluation still runs after navigation
- **WHEN** the agent has navigated and observed the outcome of a selected
  action
- **THEN** it sends the evaluation call with the existing functional, view,
  and business questions and the trace, and reports the resulting verdict

#### Scenario: Selection result is never a verdict
- **WHEN** a selection returned a recommended option
- **THEN** the report's verdict comes from the evaluation call, and the
  selected action appears in `trace` rather than as a PASS/BLOCKING judgment

#### Scenario: Jev unconfigured
- **WHEN** credentials are missing
- **THEN** no selection is performed, and affected criteria are marked
  `UNVERIFIED` with the existing `astack auth jev` guidance

### Requirement: Existing authorization, QA permissions, and data rules are preserved
Action selection SHALL NOT widen the QA write scope, the test target, or any
authorization boundary. Credentials, personal data, screenshots, and other
sensitive information SHALL NOT be included in a selection request or an
evaluation request. Screens SHALL be compressed to text before any Jev call.

#### Scenario: Selection request contents
- **WHEN** the agent sends a selection request
- **THEN** the request contains the goal, the observation compressed to text,
  and the candidate set, with no credentials, personal data, or image content

#### Scenario: Target boundary held
- **WHEN** a candidate would act outside the supplied test target
- **THEN** it is not included in the candidate set and not executed