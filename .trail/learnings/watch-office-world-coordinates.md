---
title: Office movement needs shared world coordinates rather than translated portraits
touches:
  - .agent-stack/templates/watch/office.js
  - .agent-stack/templates/watch/watch.html
  - scripts/render-watch-characters.mjs
  - tests/test-watch-office.sh
  - tests/watch-ui.mjs
---

## Decided

- The user rejected the movement between portrait cards as strange and
  requested an actual interactive office, implemented directly without
  delegating to resolver or other model agents.
- office.js owns a stable world-space floor plan: desk footprints, seated
  positions, corridors, meeting table and coffee corner. Paths use the same
  collision geometry as the visible furniture, not DOM bounding boxes.
- Render Kenney idle/walk cycles in eight authored directions. Progress the
  walk cycle by distance traveled, so stopping or yielding does not produce
  sliding feet. Seated and working clips belong at the agent's own desk.
- Office navigation is a presentation control, not permission to execute
  agents or synthesize telemetry. Keep manual visits and tours explicitly
  separate from the real activity console.

## Tried and ruled out

- Translating a front-facing canvas across roster cards: no shared floor,
  no furniture avoidance, and horizontal flipping cannot represent walking
  toward the back of a room. It also depended on responsive DOM geometry.

## Watch out

- Include occupied actor positions in the first path segment as well as
  the grid search; otherwise a replanned path can repeatedly cut across
  another actor before reaching the grid.
- Test world-space clearance for every frame during click-to-walk and
  visits, not only the final destination. Reduced motion, pause, zoom and
  changing runs must not corrupt the world state.
