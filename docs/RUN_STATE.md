# Run State

One delivery run is one directory: `.agent-stack/runs/<run-id>/` containing
`state.json`, append-only `events.jsonl`, and `evidence/`. The resolver is
the sole writer. State is local and ignored by default
(`.agent-stack/runs/` is git-ignored); only the approved summary and
artifacts are published.

## Helper

`scripts/run-state.py` implements the contract in
`.agent-stack/contracts/run-state.schema.json` and `event.schema.json`:

```sh
scripts/run-state.py --root <project> init --run <id> --change <name> ...
scripts/run-state.py --root <project> lock --run <id> --holder <session>
scripts/run-state.py --root <project> transition --run <id> --to <phase>
scripts/run-state.py --root <project> record-external --run <id> --key specPr --value <url>
scripts/run-state.py --root <project> record-code --run <id> --code-hash <sha>
scripts/run-state.py --root <project> record-verify --run <id> --command "<cmd>" --result pass --code-hash <sha>
scripts/run-state.py --root <project> resume --run <id>
scripts/run-state.py --root <project> validate --run <id> --kit-root <kit>
scripts/run-state.py --root <project> unlock --run <id>
```

## Rules

- Transitions are validated against the allowed phase graph; terminal runs
  (`awaiting_merge`, `dropped`) cannot move. Invalid moves exit nonzero.
- External side effects (issue updates, spec/implementation PR IDs) are
  recorded immediately. Retries reuse the recorded branches and PRs; resume
  discovers them instead of duplicating them. Publication failure stays
  visible in the state; the run blocks rather than silently switching modes.
- `record-code` after verification marks the run stale. A stale run must be
  re-verified before any PASS is accepted; `validate` rejects stale runs in
  `close` or `awaiting_merge`. A command string without an observed result
  is not evidence.
- Corrective rounds are counted on fix/rework transitions against
  `MAX_CORRECTIVE_ROUNDS`. Exhaustion blocks the run; it never authorizes
  shipping failed safety, correctness, or verification gates.
- The cooperative lock (`<run-id>.lock`) prevents concurrent duplicate
  delivery of one run or issue. Lock before working, unlock on close.
- On resume, re-read external state (issue, PRs) and compare artifact and
  code hashes with the recorded values. Do not trust an old PASS after the
  implementation changed.
