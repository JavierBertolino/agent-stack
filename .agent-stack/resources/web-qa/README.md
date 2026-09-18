# web-qa resources

Companion scripts for the standalone `web-qa` agent. Copied to the consuming
project as `scripts/qa/` by `setup-agent-stack.sh` (`init`/`sync` create
missing files only; existing project files are preserved).

- `ask-jev.ts` — zero-dependency Jev caller (Node 20+). Reads
  `TYPESAFE_API_KEY` from the environment, never from args or files.
- `questions.ts` — typed atomic question library (functional / view /
  business + verdict/domain/severity). Import it when building custom
  callers; `ask-jev.ts` embeds the same defaults so `--questions` can be
  omitted.

Run:

```sh
export TYPESAFE_API_KEY=...   # or: as auth jev
node --experimental-strip-types scripts/qa/ask-jev.ts \
  --state /tmp/webqa-state.json [--dims functional,view,business]
```

State shape: `{ test_goal, expected, governance, page, trace }` where
`page = { url, title, visible_copy, aria_truncated, console_errors }`.
Jev is text-only — never send screenshots; the agent compresses snapshots
to text first.
