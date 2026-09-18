# web-qa resources

Companion scripts for the standalone `web-qa` agent. Copied to the consuming
project as `scripts/qa/` by `setup-agent-stack.sh` (`init`/`sync` create
missing files only; existing project files are preserved).

- `ask-jev.ts` — zero-dependency Jev caller (Node 20+). Credentials come
  from the environment, never from args or files. Supports every Jev
  provider configured with `astack auth jev`:
  - `typesafe` (default): `TYPESAFE_API_KEY`
  - `vercel`: `AI_GATEWAY_API_KEY` (Jev model `typesafe-ai/jev-latest`;
    boolean-style `noul` questions are normalized to the Vercel evaluation
    protocol's `boolean` type)
  - `gateway`: `JEV_GATEWAY_URL` + `JEV_GATEWAY_API_KEY` + `JEV_MODEL`
    (the endpoint must expose a Jev/evaluation request contract compatible
    with the System One payload)
  - `openrouter`: preview only — exits with setup guidance until its
    System One-compatible transport is verified
- `questions.ts` — typed atomic question library (functional / view /
  business + verdict/domain/severity). Business checks are
  project-agnostic (business rules, side effects, state transitions,
  traceability). Import it when building custom callers; `ask-jev.ts`
  embeds the same defaults so `--questions` can be omitted.

Run:

```sh
export TYPESAFE_API_KEY=...   # or: astack auth jev
node --experimental-strip-types scripts/qa/ask-jev.ts \
  --state /tmp/webqa-state.json [--dims functional,view,business]
```

When Jev is not configured, the helper exits with:

```text
Jev is not configured.

Run:

  astack auth jev
```

State shape: `{ test_goal, expected, governance, page, trace }` where
`page = { url, title, visible_copy, aria_truncated, console_errors }`.
Jev is text-only — never send screenshots; the agent compresses snapshots
to text first.
