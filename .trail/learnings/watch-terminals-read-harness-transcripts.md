---
title: Watch terminals read the harness's own session record because agent notes are too sparse
touches:
  - scripts/watch.py
  - .agent-stack/templates/watch/watch.html
  - docs/watch.md
  - tests/test-watch.sh
  - tests/watch-ui.mjs
---

## Decided

- The user asked for each agent's thinking and execution to look "almost
  like the terminal/harness". `TranscriptIndex` in scripts/watch.py now reads
  Claude Code JSONL (`~/.claude/projects/<slug>*/<session>.jsonl` plus
  `<session>/subagents/agent-*.jsonl` + `.meta.json` agentType) and OpenCode
  2.x SQLite (`session_v2` + `session_message`, opened `mode=ro`,
  `query_only`) and serves them at `/api/transcript?since=<seq>`. This
  replaces the earlier "no session-store scraping" stance on purpose.
- Scope is the safety boundary: project root or below (Claude `cwd`, OpenCode
  `directory`), sessions that mention the run id plus their subagents, and
  the run window (first event − 15 min .. last event + 10 min, or now while
  open). Secrets are redacted server-side; output is clipped at 200 lines /
  12 KB. `--no-transcripts` disables it entirely.
- Attribution: Claude main session = resolver (it delegates via the Agent
  tool, see adapters/claude/adapter.md); subagent = meta `agentType`.
  OpenCode session `agent`; a root session = resolver. If a `resolver`
  subagent exists, the main session is "main", not resolver.
- Tool results are separate entries with `callId`; the page patches the
  existing tool entry in place, so expanded output and scroll survive.

## Tried and ruled out

- Relying on `note` telemetry: in the real calc-studio run the designer
  worked 2.5 minutes and emitted zero notes; the resolver emitted two.
- OpenCode v1 tables (`session`/`message`/`part`): they stopped updating
  after the 2.x migration, so only `session_v2`/`session_message` are read.

## Watch out

- Claude Code stores most thinking blocks with empty content. Show "content
  not stored by Claude Code", never synthesize it. OpenCode stores real
  reasoning text.
- Redaction rules can stack: the generic `key=value` rule must skip values
  already replaced (`(?!\[redacted)`), or `sk-…` becomes `[redacted] key]`.
- Claude project slugs share prefixes (`calc-studio` vs `calc-studio-2`):
  always re-check each entry's `cwd` against the root.
- `⏺` renders as a color emoji on Linux fonts; the terminal uses `●`.
- OpenCode assistant messages update in place while streaming: emit
  reasoning/text only once the message completed or a later item exists, and
  emit a tool's result when its state reaches completed/error.
