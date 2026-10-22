---
name: rundown
description: Summarize what shipped across one or more repositories in a time window (e.g. "/rundown last 7 days"). Writes an agent-facing Markdown rundown with manual test cases for web-qa and mobile-qa, plus a self-contained HTML page for humans.
metadata:
  version: "1.0"
  consumer: user, resolver, web-qa, mobile-qa
  stage: rundown
---

# Rundown

The delivery loop ships many small changes. A rundown turns one time
window of that work into two files built from the same evidence:

- `reports/rundown/<slug>.md` — the agent copy. Source of truth. Carries
  manual test cases that `web-qa` and `mobile-qa` execute.
- `reports/rundown/<slug>.html` — the human copy. Plain language, no
  diffs, readable by someone who did not follow the work.

This skill is read-only on every repository it inspects. It writes only
the two report files.

## 1. Resolve the window

Parse the argument into an inclusive `[since, until]` window in the local
time zone, then restate it with absolute dates and the zone before doing
any work (`2026-10-15 00:00 → 2026-10-22 23:59 -03:00`).

- Relative: `last 7 days`, `last 2 weeks`, `yesterday`, `this week`,
  `last sprint` (ask for the sprint dates; never guess them).
- Absolute: `since 2026-10-01`, `2026-10-01..2026-10-15`,
  `from <date> to <date>`.
- No argument: ask once for the window. Offer `last 7 days` as the default.

## 2. Resolve the repositories

1. Explicit repo paths in the argument win.
2. Otherwise, when the current directory is inside a git work tree
   (`git rev-parse --show-toplevel` succeeds), use that repository only.
3. Otherwise, list git repositories directly below the current directory
   (depth 2, skipping `node_modules`, `.worktrees`, and vendored trees) and
   ask once which to include. Default to all of them.
4. Deduplicate linked worktrees by `git rev-parse --git-common-dir` so one
   repository never appears twice.

For each repository record: name, path, remote `<owner>/<repo>` when present,
default branch (`gh repo view --json defaultBranchRef` or
`git symbolic-ref refs/remotes/origin/HEAD`), and the HEAD SHA of that
branch at the time of the rundown.

## 3. Collect evidence (per repository, read-only)

"Shipped" means merged into the default branch (or a release branch the
project declares) inside the window. Merged is not deployed: report
deployment only from evidence (release tags, deploy workflow runs).

Gather, in this order, stopping where a source is unavailable and noting
the gap:

1. Merged PRs: `gh pr list --state merged --base <default>` with a
   `merged:<since>..<until>` search and `--json` fields for number, title,
   body, url, author, mergedAt, labels, files, headRefName. Page until the
   window is covered.
2. Direct commits: `git log <remote>/<default> --first-parent
   --since=<since> --until=<until>` (fetch first only when the user allows
   network access). Commits not belonging to a merged PR are listed as
   direct pushes.
3. Specs: OpenSpec changes archived or added in the window
   (`openspec/changes/archive/`, `openspec/specs/`). Their `WHEN`/`THEN`
   scenarios are the best source of test steps.
4. Issues linked from PR bodies or branch names (Linear, Jira, Trello)
   through the connected MCP servers. Read acceptance criteria; never
   update an issue from this skill.
5. Delivery runs in `.agent-stack/runs/*/state.json` updated in the window:
   change id, verification evidence, PR links.
6. Releases and tags in the window (`gh release list`, `git tag
   --contains`), plus `CHANGELOG.md` entries.
7. Open PRs updated in the window: listed as in flight, never as shipped.

Without `gh` or network access, fall back to local git history and say so
in the rundown's Gaps section.

## 4. Build the item list

Group commits into one item per merged PR (or per direct commit). For
each item decide:

- **Surface**: `web`, `mobile`, `api`, `cli`, `infra`, `docs`, or
  `internal`, from changed paths and project layout (app directories,
  `package.json` scripts, Android and iOS projects, route files, API
  handlers). An item can touch several surfaces.
- **Kind**: feature, fix, change, removal, refactor, chore, security.
- **User impact**: one plain sentence a non-engineer understands. When
  the PR does not say who is affected, write `Impact unclear` instead of
  guessing.
- **Risk**: `high` (money, auth, data migration, permissions, deletion),
  `medium` (user-visible flow changes), `low` (copy, styling, internal).
- **Provenance**: `Declared` when backed by a spec, issue, or PR test
  plan; `Inferred` when derived only from reading the diff.

## 5. Write manual test cases

Every item on `web`, `mobile`, `api`, or `cli` with user-visible behavior
gets at least one test case. Items without manual coverage (refactors,
CI, docs) say why and name the automated checks that cover them.

Write cases for an agent that has never seen the code:

- Derive steps from spec scenarios first, then issue acceptance criteria,
  then the PR test plan, then the diff. Mark diff-only cases `Inferred`.
- One observable action per step, each with an expected result the tester
  can see on screen or in a response. No "verify it works".
- Name the entry point: route path, screen name, deep link, endpoint, or
  command. Use placeholders such as `<base-url>` and `<test-user>`; never
  write real credentials, tokens, customer data, or production URLs that
  the project does not already document.
- State preconditions: role or account type, seed data, feature flags,
  platform (iOS/Android/desktop/mobile web), app build.
- Add at least one negative or edge case for `high`-risk items
  (permission denied, invalid input, empty state, retry after failure).
- Tag dimensions the QA agents judge: `functional`, `view`, `business`.
- Add cleanup steps when a case creates or changes data.
- Order cases by risk, then by surface.

Case ids are `RD-<n>`, stable within one rundown.

## 6. Markdown format (agent copy)

```md
---
rundown: 1
window: { since: <iso>, until: <iso>, timezone: <zone> }
generated: <iso>
repos:
  - { name: <name>, remote: <owner/repo>, branch: <default>, head: <sha> }
counts: { shipped: <n>, in_flight: <n>, test_cases: <n>, web: <n>, mobile: <n> }
---

# Rundown: <since> → <until>

## How QA agents use this file
web-qa runs every case with `surface: web`; mobile-qa runs every case with
`surface: mobile`. Run in listed order. Report each case id with PASS,
BLOCKING, NIT, or UNVERIFIED. A missing precondition makes the case
UNVERIFIED; never improvise around it.

## Summary
<3–6 bullets: what changed for users this period>

## Shipped
### <repo> #<pr> — <title>
- Merged: <iso> by <author> · <url>
- Surface: <surfaces> · Kind: <kind> · Risk: <risk> · Provenance: <Declared|Inferred>
- Impact: <plain sentence>
- Links: <issue>, <spec change>, <release>
- Tests: RD-1, RD-2 | No manual test: <reason>; covered by <checks>

## Manual test cases
### RD-1 — <short goal>
- Item: <repo> #<pr>
- Surface: web | Platform: <desktop|mobile web|iOS|Android|any>
- Risk: <risk> · Dimensions: functional, view, business · Provenance: <...>
- Entry: `<base-url>/<path>` | <screen> | <deep link>
- Preconditions: <account/role, seed data, flags, build>
- Steps:
  1. <action> → Expected: <observable result>
  2. <action> → Expected: <observable result>
- Edge cases: <negative or empty-state checks>
- Cleanup: <how to revert created data> | none

## In flight (not shipped)
- <repo> #<pr> — <title> · <state>

## Gaps
- <sources that were unavailable, items with unclear impact, missing preconditions>
```

Keep the field labels exactly as above so QA agents can filter by them.

## 7. HTML format (human copy)

One self-contained file: inline CSS, no scripts required, no external
fonts, images, or CDNs, so it opens offline and survives being emailed.
Escape every value taken from PRs, issues, or commits.

- Header: window with absolute dates, repositories, generated time.
- Headline numbers: shipped items, repositories, test cases, high-risk items.
- "What changed" first: a short plain-language summary grouped by
  product area or user type, not by repository internals.
- One card per shipped item: title rewritten in plain words, impact
  sentence, kind and risk badges, links to the PR, issue, and spec.
- "What we will verify": a table of test cases (id, goal, surface, risk,
  status `Not run yet`). Steps stay in the Markdown file.
- In flight and Gaps sections, collapsed with `<details>`.
- Readable at phone width; respects `prefers-color-scheme`; semantic
  headings; sufficient contrast; badges never rely on color alone.

Avoid jargon (SHA, rebase, first-parent, refactor) in prose; say what
changed and who notices it.

## Output

- Write both files under `reports/rundown/` of the current repository, or
  of the current directory when the rundown spans several repositories.
  Slug: `<since>_<until>` plus `-<repo>` for single-repository runs.
- Never overwrite an existing rundown for the same slug without asking;
  offer a suffixed name instead.
- Reply with both paths, the counts, the high-risk items, and the gaps.
  Do not paste the full rundown into the reply.

## Evidence

Every item cites its source (PR URL, commit SHA, spec path, issue key).
The front matter records each repository's HEAD SHA so a later reader
knows exactly what the rundown covered.

## Failure behavior

- A repository that cannot be read is listed in Gaps; the rundown
  continues with the others.
- An empty window produces a rundown that says nothing shipped, never an
  invented summary.
- Never checkout, reset, stash, commit, push, or edit files in the
  inspected repositories. Network fetches only with permission.
- Redact anything that looks like a secret, token, personal data, or
  customer record before writing either file.
