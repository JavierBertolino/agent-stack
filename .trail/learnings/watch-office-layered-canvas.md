---
title: The watch office renders a cached scene plus a dirty-rect actor layer at device resolution
touches:
  - .agent-stack/templates/watch/office.js
  - .agent-stack/templates/watch/watch.html
  - .agent-stack/templates/watch/characters.json
  - scripts/render-watch-characters.mjs
  - tests/test-watch.sh
---

## Decided

- The user reported the office as slow, ugly and low resolution. A CPU
  profile showed `fill` + `drawImage` re-rasterizing the whole 2360×1360
  canvas at 60 fps (~50% of a core idle). office.js now keeps two canvases:
  a scene layer (floor, furniture, desk plates) recomposed only when a desk
  signature changes (≤ ~8/s), and an actor layer that clears and redraws
  only dirty rectangles. Idle script time fell from ~1.5 s to ~0.04 s per 3 s.
- Both canvases are backed at devicePixelRatio × zoom (capped at 9 Mpx each)
  while the world div keeps its CSS `scale()`, so zoom no longer blurs.
- Atlas v3: 2× render scale inside a margin, per-sequence crops, one WebP
  sheet per character, `[sx,sy,w,h,ax,ay]` tiles. The generator throws if a
  frame touches the render frame. v2 clipped hands (`idle-s` reached
  x = 0..191 of a 192 cell).
- Seated agents face the camera behind the desk; working = Kenney `drive`
  clip (reads as typing), otherwise `sit`. The monitor sits at the desk's
  right corner turned three-quarters, glowing by status. Desk plates show
  the latest real action. They replaced floating thought cards that collided
  with the window band.
- A* uses a binary heap and memoized static cell edges (worst path 13.5 ms
  → ~1 ms). The exact segment-to-actor check is stricter than the sampled
  `clearSegment`, so test-watch-office.sh still validates every route.

## Tried and ruled out

- Seated characters facing the monitor (back to camera): only the back of
  the head shows and the characters lose their personality.
- A laptop lid in front of the agent: it hid the lower face.

## Watch out

- Furniture sprites double as occluders, re-drawn over characters clipped to
  their bounds. Keep them opaque. Contact shadows and status glows belong in
  the floor/scene layer, or they darken twice over a character.
- A seated sprite spans anchor −60..+18 world units; `SEAT_DY` decides where
  the desk edge cuts the body. The chair back goes behind the torso, not
  around the head.
- Anything that changes a plate (status, activity text, selection, staleness
  at 20 s) must be part of the plate signature, or the scene never recomposes.
