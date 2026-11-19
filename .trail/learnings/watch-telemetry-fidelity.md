---
title: Watch activity must distinguish agent notes from report evidence
touches:
  - .agent-stack/templates/watch/watch.html
  - .agent-stack/roles/resolver.md
  - .agent-stack/roles/designer.md
  - scripts/watch.py
---

## Decided

- The user rejected the RPG transcript because invented dialogue displaced
  useful activity. In watch.html, separate real activity (commands, results,
  public decision summaries) from team interactions (handoffs and reports).
  Do not present browser-generated flavor as an agent's thinking.
- Use original Kenney Mini Characters CC0 artwork, rendered offline into
  characters.json, rather than recoloring the old RPG portraits. Embedding
  the atlas in watch.py preserves offline runtime behavior.
- A report's commands are historical evidence, not live command events.
  Label their provenance and receipt timestamp explicitly. An absent note
  is unknown, not an invitation to synthesize a decision.

## Tried and ruled out

- Assuming all roles can run the telemetry CLI: designer denies shell and
  review roles have bounded write permissions. A code worktree also need
  not contain the run-state directory. Pass the root in delegations and
  relay allowed public notes through resolver without bypassing permissions.
- Inferring execution from handoffs or phase alone: a QA spawn can be
  rejected while a handoff still exists. Show delegated/awaiting notes,
  and do not attribute resolver-executed checks to the rejected specialist.

## Watch out

- Report status done describes completing the review, not its verdict.
  BLOCKING must take precedence.
- The installer reads the first duplicate config key. watch.py must do the
  same or displayed effort can disagree with the generated agents.
- Preserve scroll and expanded detail state on polling. Idle heartbeats
  should not rebuild the console DOM.
