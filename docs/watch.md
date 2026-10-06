# Watch mode (live teaching overlay)

`astack watch` serves a read-only live view of one delivery run for demos
and teaching. It renders the resolver pipeline, the active agent, handoffs
and reports, full Jev request/response bodies, OpenCode model routing, and
self-reported token usage.

```sh
cd my-project
astack watch --run <run-id> --port 4311 --open
```

OpenCode-first: the viewer is a single self-contained page with no external
requests, so it works offline on any harness. Other harnesses reuse the same
events later; only the model labels in `/api/meta` are OpenCode-specific
today.

## Scope

- Live only. The server tails `.agent-stack/runs/<run-id>/state.json` and
  append-only `events.jsonl` and polls from the browser every second.
  There is no replay fixture and no static export.
- Read-only. The server implements GET only (`/`, `/api/state`,
  `/api/events?since=N`, `/api/meta`); POST/PUT/DELETE/PATCH return 405.
  Pausing freezes this page only. The server never writes to the run.

## Telemetry event types

`detail` is always a string; structured payloads are JSON-encoded so the
existing `event.schema.json` shape is unchanged:

| type | emitter | detail JSON |
|---|---|---|
| `agent-start` | every agent on entry | `{"agent":"developer","model":"..."}` |
| `agent-end` | every agent on exit | `{"agent":"developer","status":"done\|partial\|blocked"}` |
| `handoff` | resolver before delegation | full `handoff.schema.json#1` |
| `report` | resolver when a subagent report arrives | full `report.schema.json#1` |
| `jev-request` | web-qa / mobile-qa before each Jev call | full `{model,state,questions}` |
| `jev-response` | web-qa / mobile-qa after each Jev call | full verdict JSON |
| `usage` | every agent at exit (option A) | `{"agent":"...","model":"...","input":N,"output":M,"cacheRead":0,"cacheWrite":0,"total":T,"source":"self-reported"}` |

Only the resolver may use `transition` and `record-*`; telemetry types
never change phase or budget. Subagent telemetry appends to `events.jsonl`
(plus an `updatedAt` bump) so the view updates while the subagent still runs.

## Models

`/api/meta` resolves per-role model and thinking from the target project's
`.agent-stack/config.conf` (`OPENCODE_*_MODEL`, `OPENCODE_*_VARIANT`) plus
`JEV_PROVIDER` / `JEV_MODEL`. Empty model means harness default;
`web-qa` / `mobile-qa` use `inherit` by default. This strip is
deterministic and always present, even before any agent reports usage.

## Token usage (option A: self-reported)

Each agent copies input/output totals from the harness session stats it can
see into one `usage` event at `agent-end`. Omit unknown fields rather than
guessing. The viewer sums per-agent totals into a global marker plus a
stacked breakdown and labels everything estimated, self-reported, and not
for billing. Agents that have not reported yet render as n/a, never zero.

## Redaction

Full Jev bodies render collapsed with expand and copy controls. Full means
the complete `{model,state,questions}` request and verdict response — never
credentials. Never emit `TYPESAFE_API_KEY`, `AI_GATEWAY_API_KEY`,
`JEV_GATEWAY_API_KEY`, session tokens, or unrelated runs. If a secret
appears in the view, stop the run and rotate it.

## Troubleshooting

- `no such run`: the server binds per run; create it first with
  `astack run-state init --run <id> ...`.
- Port in use: pass `--port 0` for an ephemeral port; the actual URL prints
  to stdout.
- Large Jev payloads (up to the 10 MiB `ask-jev.ts` limit) render collapsed;
  expansion may be slow on very large checkpoints — this is expected for
  full-body teaching.

## Future (option B, deferred): harness-scraped usage

Option A is intentionally self-reported so the overlay works without
harness coupling. A follow-up may scrape exact counters from the OpenCode
session store instead of asking each agent to paste them:

- The viewer contract does not change: the server would still serve `usage`
  events (same shape, `source:"opencode-sessions"`) and the same
  aggregation.
- What changes: `scripts/watch.py` (or a sidecar collector) reads the
  OpenCode session JSONL for the active session, maps session segments to
  run agents, and synthesizes `usage` entries; role prompts drop the
  self-report step for OpenCode runs.
- Open questions before building B: stable on-disk session path across
  OpenCode versions, mapping subagent segments to resolver runs, behavior
  when the store is absent (fall back to A with n/a rows), and whether
  scraping needs explicit opt-in for public demos.
- Until then, B stays out of scope: live-only, read-only, A-only.
