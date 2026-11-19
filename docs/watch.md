# Watch mode — Agent Studio

`astack watch` opens a read-only workspace for observing a delivery run:
which agent is working, what it reports doing, and how it hands work to
the rest of the team.

```sh
cd my-project
astack watch --open           # follow the latest run, even before one exists
astack watch --run <run-id>   # pin a particular run
astack watch --no-transcripts # telemetry only; never read harness sessions
```

## Workspace

The viewer is one screen with no page scroll on desktop: a one-line header
(run, phase progress, clock, connection, harness, **Models & tokens** menu,
run picker, pause, sound), the **office** on the left, fitted to its column
and refitted when the window resizes, with **Team interactions** in the
space below it, and the **agent terminal** on the right at full height. On
narrow screens the panels stack.

Seven Kenney Mini Characters inhabit a real office floor plan: individual
desks, chairs, monitors, a shared meeting table and a coffee corner. The
roles are resolver, designer, design-qa, developer, web-qa, mobile-qa and
Jev (the robot).

Agents sit behind their desks facing you. Each desk has a monitor turned
three-quarters toward the room that glows by status, and a **desk plate**
with the agent's name, status and latest real action (`✻` thinking, `$`/`●`
command or tool, `›` message, `✓` result, `✗` error), taken from the harness
transcript when there is one and from reported notes otherwise. An agent
that is working types at the keyboard; others sit.

Original idle/walk clips are pre-rendered in **eight directions**, alongside
seated (`sit`) and typing (`drive`) clips, at **2× resolution** and cropped
per sequence, so sprites stay sharp on HiDPI screens and when zoomed.

Rendering uses two Canvas 2D layers sized to the device pixel ratio × zoom:

- the **scene** layer caches floor, walls and furniture and is recomposed
  only when a desk changes (status, latest action, selection), at most about
  eight times a second;
- the **actor** layer redraws only dirty rectangles around characters that
  moved or advanced an animation frame, re-drawing furniture in front of a
  character clipped to that character.

An idle office therefore costs almost no main-thread time. Pathfinding uses
A* with a binary heap over a cached static grid; characters follow corridors
rather than crossing desks. The walk cycle advances with distance traveled,
including when yielding to another character. There is no Three.js, WebGL,
CDN or asset request at runtime: the server embeds `office.js` and the atlas
into the page. Missing art falls back to labeled initials.

### Interactive office controls

These controls affect presentation only. **They never launch agents, consume
tokens, modify source code or append simulated telemetry.**

1. Click a character (or its terminal tab) to select it; the terminal then
   shows only that agent, and **All agents** shows everyone again. Each tab's
   tooltip carries the agent's status, model and effort.
2. Click clear floor to walk there (the coffee corner too). Furniture blocks
   movement; the route around it is highlighted. The focused floor canvas
   also accepts arrow keys.
3. Click another desk to visit it. The character walks over, pauses for an
   explicitly labeled office interaction, then returns to its own desk.
   Clicking your own desk walks you home. Desks are keyboard-focusable.
4. **Everyone to desks** sends everybody home. **Tour** queues two labeled
   presentation visits.
5. **−**/**+** zoom by hand (which stops auto-fit); **Fit** fits the whole
   floor again and resumes following the window size.

Live handoffs and reports use the same movement engine. Their bubbles
contain reported notes, handoff goals, report summaries or explicitly
labeled status, never invented private reasoning. Historical events are
not reenacted as live walks on page load.

A **Jev request** is a call, not a visit: Jev walks from the QA desk to the
requester, answers at their desk, and walks back. That is presentation of
the recorded request/answer exchange, not an extra model call.

The header and the office stage show the **harness** running Agent Stack
(for example `OpenCode · astack 0.1.4`), taken from the project's installed
platform markers and configuration. It is reported as configuration, not as
observed telemetry, and tools that embed a different host can pass
`--harness` to override it.

Reduced motion shows conversations without animated travel; direct manual
navigation changes position instantly. Pause freezes positions and animation
clocks. Audio is optional and off by default on each page load.

- **Agent terminals**: each agent's session rendered the way its harness
  shows it — `●` tool calls with their full command or path, `⎿` output
  (eight lines, expandable; reads summarized as "Read N lines"), edit and
  write diffs, `✻` thinking, visible messages, the user prompt or the
  resolver's delegation prompt, and `─` lifecycle lines (started, handoff,
  report, finished). Tabs switch between agents (with a live dot and an
  entry count) or interleave everyone. A running tool shows `running…` until
  its result arrives, and the result is patched into the same entry. New
  entries are inserted in place, so scroll position, expanded output and
  open details survive polling. Filter by type (thinking, commands & tools,
  results & output, messages & prompts, errors, reported notes only) or
  search across commands and output. Agent-reported notes appear alongside,
  labeled as reported; commands/results recovered from `report.commands`
  are labeled as report evidence with report receipt timestamps.
- **Team interactions**: handoffs show sender, recipient and acceptance
  criteria; reports show actual results, verdict, blockers and next action.
  Phase changes and Jev questions/answers appear here too. There is no
  invented dialogue or RPG narration.
- **Reading behavior**: entries are ordered oldest-to-newest; Following
  keeps the newest entry in view. Scrolling up holds your place.
  “Jump to latest” resumes following. Expanded event details survive
  incoming entries and idle polling. Details can be copied.
- **Models & tokens** (header menu): complete model routing and
  self-reported token tables. Unknown usage is `n/a`, never zero. No fabricated XP or estimated
  “thinking” is shown as agent output.

The header shows phase and elapsed wall time from recorded events (which
can include overnight pauses). Finished runs stop the timer at their last
recorded event. Pause freezes this viewer, not the running agents.
Space toggles pause outside form controls; M toggles audio.

## Truthfulness and missing telemetry

Thinking is shown only when the harness itself stored it. OpenCode records
the model's reasoning text; Claude Code usually records thinking blocks with
their content withheld, which the terminal shows as “content not stored by
Claude Code” instead of guessing. Agent-reported `kind:"thought"` notes are
brief public decision summaries and are labeled as reported. The viewer
never invents reasoning or activity.

An entry event is direct evidence that an agent started. A handoff alone
means **delegated**, not that the specialist definitely ran. A report
updates the reported specialist's status even when start/end events are
missing. `BLOCKING` takes precedence over a report's `status:"done"`.
Roles with no events show **No telemetry**, not “idle”. Transcript activity
is direct evidence that an agent is working; a subagent session that ended
without an `agent-end` event shows **Session ended**, not Done. An
unfinished lifecycle in a terminal run shows **No end reported**.

Role identity is taken from the event. Legacy runs that filed
resolver-executed web QA as `role:"design-qa"` retain that attribution;
consult their event details for deviations. The viewer does not rewrite
historical evidence or guess the actual executor from prose.

## Harness transcripts

Self-reported notes are sparse (an agent can work for minutes without
emitting one), so the terminals read what the harness already records on
this machine, read-only:

| Harness | Source | Agent attribution |
| --- | --- | --- |
| Claude Code | `~/.claude/projects/<project-slug>*/<session>.jsonl` (or `$CLAUDE_CONFIG_DIR/projects`) and `<session>/subagents/agent-*.jsonl` | main session = resolver; subagent = its `agentType` from `agent-*.meta.json` |
| OpenCode | `$XDG_DATA_HOME/opencode/opencode.db` (default `~/.local/share/opencode/opencode.db`; override with `ASTACK_OPENCODE_DB`), tables `session_v2` / `session_message` | the session's `agent`; a root session = resolver |

If the resolver itself runs as a subagent, the main session is shown as
**Main session** instead. Scope rules:

- only sessions whose working directory is the project root or below it;
- only sessions that mention the run id, plus their subagent sessions;
- only entries inside the run's window: 15 minutes before its first event
  until 10 minutes after its last event (or now, while the run is open).

Values that look like credentials (API keys, tokens, bearer headers,
`password=`/`secret=`/`token=` assignments, private keys) are redacted on
the server before anything reaches the page. Tool output is clipped at 200
lines / 12 KB per call and labeled when clipped. The OpenCode database is
opened with `mode=ro` and `query_only`; Claude Code files are only read.
Older OpenCode versions that predate `session_v2` are not read; their runs
fall back to reported notes. Pass `--no-transcripts` to never read either
store.

## Telemetry

The server tails `.agent-stack/runs/<run-id>/state.json` and append-only
`events.jsonl`. Existing event types and schemas are unchanged.
`detail` is a string containing JSON for structured payloads:

| Type | Detail |
| --- | --- |
| `agent-start` | `{"agent":"developer","model":"provider/model","variant":"high"}` (omit unknown model/variant) |
| `agent-end` | `{"agent":"developer","status":"done\|partial\|blocked"}` |
| `note` | `{"agent":"developer","kind":"thought\|command\|result\|error\|activity","doing":"..."}` |
| `handoff` | full handoff contract; optional `targetAgent` disambiguates the recipient |
| `report` | full report contract, including observed `commands`/`results` |
| `jev-request` | full `{agent,model,state,questions}` body, no credentials |
| `jev-response` | full judgement body |
| `usage` | `{"agent":"...","input":N,"output":M,"total":T,"source":"self-reported"}` (omit unknown values) |

From a code worktree, address the **run-state project root** explicitly:

```sh
astack run-state --root <run-state-project-root> event --run <run-id> \
  --type note \
  --detail '{"agent":"developer","kind":"thought","doing":"Keeping click and keyboard inputs on the same state transition to avoid divergence."}'
```

Only the resolver uses `transition` and `record-*`. Telemetry never changes
the phase or corrective budget. A specialist without event-writing
permission returns public notes to the resolver rather than bypassing
its role restrictions. Resolver-executed work stays attributed to resolver.
Unattributed verification events appear as **Run**, not an invented agent.

## Models and usage

Reported entry models/effort take precedence over project configuration;
the model tooltip identifies the source. Otherwise `/api/meta` uses
`OPENCODE_*_MODEL` / `OPENCODE_*_VARIANT` from `.agent-stack/config.conf`.
First occurrence wins, matching the installer. `inherit` resolves to
the resolver model when known, marked inherited.

Usage is self-reported, not billing data. Missing fields stay unknown;
input + output produces a total only when both numbers were supplied.
Token tables do not read harness session stores.

## Read-only and offline

The server implements GET for `/`, `/api/runs`, `/api/state`,
`/api/events?since=N`, `/api/transcript?since=N` and `/api/meta`.
POST/PUT/DELETE/PATCH return 405. There are no runtime requests beyond these
same-origin APIs. The server binds to 127.0.0.1 by default; transcripts
contain your sessions' commands and output, so do not expose it on a shared
network address. Never emit API keys, session credentials or unrelated run
data. Redaction is pattern-based, not a guarantee: if a credential appears,
stop the run and rotate it.

## Artwork and verification

Original artwork: [Kenney Mini Characters 2.0](https://kenney.nl/assets/mini-characters),
CC0. License and provenance live beside the template in
`KENNEY-LICENSE.txt`; `characters.json` (atlas v3) records the source GLBs,
clips, directional sequences, per-sequence crops and ground anchors, and one
WebP sheet per character. The generator renders at 2× (`ATLAS_SCALE`) inside
a margin and fails if any frame still touches the render frame, so hands and
heads are never clipped.
To regenerate after downloading and unpacking the official pack:

```sh
npm install --prefix <temporary-directory> three@0.181.1 playwright@1.56.1
node scripts/render-watch-characters.mjs <unpacked-pack> \
  <temporary-directory>/node_modules \
  .agent-stack/templates/watch/characters.json
```

The generator uses Chromium (`CHROMIUM_PATH` can override its executable).
These are development-only dependencies, not installation prerequisites.

`sh tests/test-watch-office.sh` checks reachability and obstacle clearance
from every desk to coworkers, the walkway and coffee corner.
`sh tests/test-watch.sh` checks contracts, API read-only behavior,
embedded sprites, missing-art fallback, config precedence, and transcript
scoping (project boundary, run membership, subagents, OpenCode sessions),
redaction, clipping, diffs and incremental reads against fixture sessions.
The optional browser regression suite covers the transcript terminal
(running tools patched in place, untrusted text, thinking markers), real
attribution, filters,
untruncated commands, report evidence, verdict precedence, scroll/expansion
retention, desk selection, click-to-walk, per-frame collision checks,
conversations, return-to-desk, coffee, pause, reduced motion, zoom,
keyboard behavior, mobile layout, run switching, absence of fake telemetry
and absence of external requests:

```sh
node tests/watch-ui.mjs <temporary-directory>/node_modules
```

Port occupied? Pass `--port 0` to choose an available one.
Template and atlas changes require restarting the watch server; the page
is loaded once at startup.
