# web-qa resources

Companion scripts for the standalone `web-qa` agent. Copied to the consuming
project as `scripts/qa/` by `setup-agent-stack.sh` (`init`/`sync` create
missing files only; existing project files are preserved).

- `ask-jev.ts` — zero-dependency Jev caller (Node 20+). Reads the Jev provider
  selection and credentials from environment variables loaded by `astack`.
- `questions.ts` — typed atomic question library (functional / view /
  business + verdict/domain/severity). Import it when building custom
  callers; `ask-jev.ts` embeds the same defaults so `--questions` can be
  omitted.

Run:

```sh
astack auth jev
node --experimental-strip-types scripts/qa/ask-jev.ts \
  --state /tmp/webqa-state.json [--dims functional,view,business]
```

State shape: `{ test_goal, expected, governance, page, trace }` where
`page = { url, title, visible_copy, aria_truncated, console_errors }`.
Jev evaluates structured text state — never send screenshots; the agent compresses snapshots
to text first.
