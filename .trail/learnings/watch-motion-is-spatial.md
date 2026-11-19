---
title: Watch characters must walk between coworkers, not only animate in place
touches:
  - .agent-stack/templates/watch/watch.html
  - scripts/render-watch-characters.mjs
  - tests/watch-ui.mjs
---

## Decided

- The user clarified that animated portraits are insufficient: characters
  should move through the workspace and talk to each other. In watch.html,
  live handoffs and reports trigger a walk to the recipient, conversation,
  and return to the sender's desk, using Kenney's original walk clip.
- Bubbles contain actual reported activity or explicitly labeled status.
  Motion previews must say they are previews and never append fake telemetry.

## Watch out

- Nearby avatars need a shared bubble layout. Positioning both bubbles
  directly above their respective heads makes the text overlap. The browser
  regression suite verifies separation as well as return-to-desk.
- Reduced motion shows the exchange without travel; pause freezes the motion
  clock. Loading historical events should not reenact them as live work.
