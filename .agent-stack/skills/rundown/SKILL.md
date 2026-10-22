---
name: rundown
description: Summarize which features shipped across one or more repositories in a time window and base branches (e.g. "/rundown last 7 days into main,dev"). Writes an agent-facing Markdown rundown with manual test cases for web-qa and mobile-qa, plus a self-contained HTML page for humans.
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

It answers three questions: which features shipped, how far each one got
(only on an integration branch, or released), and how to verify them.

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

An `into <branch>[,<branch>]` clause (`into main,dev`) selects base
branches for §3; parse it here.

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
and default branch (`gh repo view --json defaultBranchRef` or
`git symbolic-ref refs/remotes/origin/HEAD`).

## 3. Resolve the base branches

A base branch is a branch work merges into: the default branch and any
integration branch before it (`dev`, `develop`, `staging`, `release/*`).

1. Branches named with `into` win. A named branch missing from a
   repository is listed in Gaps for that repository.
2. Otherwise count merges inside the window for the default branch and
   for remote branches named `main`, `master`, `dev`, `develop`,
   `development`, `staging`, or `release/*`. When only the default branch
   has merges, use it without asking. Otherwise ask once, as a
   multi-select showing each branch with its merge count, the default
   branch preselected. In a multi-repository rundown, ask once with the
   branches grouped by repository.
3. Order the selected bases from least to most promoted. Default order:
   `dev`/`develop`/`development` → `staging` → `release/*` →
   `main`/`master`. When the order is not obvious, ask with the rest of
   the questions in this step. The last base is the release branch.

Record each base's HEAD SHA at the time of the rundown. Stages in §5
describe the branches as they are now, not as they were at `until`.

## 4. Collect evidence (per repository and base, read-only)

"Shipped" means merged into a selected base inside the window. Merged is
not deployed: report deployment only from evidence (release tags, deploy
workflow runs).

Gather, in this order, stopping where a source is unavailable and noting
the gap:

1. Merged PRs per base: `gh pr list --state merged --base <base>` with a
   `merged:<since>..<until>` search and `--json` fields for number, title,
   body, url, author, mergedAt, mergeCommit, labels, files, headRefName.
   Page until the window is covered.
2. Direct commits per base: `git log <remote>/<base> --first-parent
   --since=<since> --until=<until>` (fetch first only when the user allows
   network access). Commits not belonging to a merged PR are listed as
   direct pushes.
3. Specs: OpenSpec changes archived or added in the window
   (`openspec/changes/archive/`, `openspec/specs/`). Their `WHEN`/`THEN`
   scenarios are the best source of test steps.
4. Issues linked from PR bodies or branch names (Linear, Jira, Trello)
   through the connected MCP servers. Read titles and acceptance criteria;
   never update an issue from this skill.
5. Delivery runs in `.agent-stack/runs/*/state.json` updated in the window:
   change id, verification evidence, PR links.
6. Releases and tags in the window (`gh release list`, `git tag
   --contains`), plus `CHANGELOG.md` entries.
7. Open PRs updated in the window: listed as in flight, never as shipped.

Without `gh` or network access, fall back to local git history and say so
in the rundown's Gaps section.

Then separate three kinds of merge before building items:

- **Promotions**: a PR or merge whose source is another selected base
  (`dev` → `main`, `release/*` → `main`). A promotion moves existing work;
  it is never a shipped item. List promotions with date and PR.
- **Reverts**: a PR titled `Revert "…"` or a commit containing
  `This reverts commit <sha>`. When the reverted change merged inside the
  window, the original item is `reverted`, not shipped. When it merged
  earlier, the revert is its own item of kind `removal`.
- **Back-merges**: a merge from a later base into an earlier one
  (`main` → `dev`). Used only to check hotfixes in §5; never an item.

## 5. Build items, stages, and features

**Items.** One item per merged PR (or per direct commit) that is not a
promotion or back-merge. For each item decide:

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

**Stage.** With one base selected, every item is `released` on that base.
With several, check whether each item reached each later base, trying
these methods in order and recording which one answered:

1. `ancestry`: `git merge-base --is-ancestor <merge-sha> <remote>/<later>`.
   Conclusive for merge commits and fast-forwards.
2. `patch`: `git cherry <remote>/<later> <merge-sha> <merge-sha>^` prints
   `-` for every listed commit whose equivalent change already exists
   there (cherry-picks, rebases, per-feature squashes).
3. `reference`: a promotion PR into the later base lists the item's PR
   number or commit in its body, commits (`gh pr view --json commits`),
   or squash message.

Then assign:

- `released` — reached the release branch.
- `staged` — on an earlier base only, and no promotion into the next
  base happened after it merged. Name the furthest base it reached.
- `hotfix` — merged directly into a later base. Check it against earlier
  bases with the same methods; when it is missing from one, report
  `hotfix, missing from <base>` so the team can back-merge.
- `unclear` — a promotion happened after the item merged, but no method
  confirmed it was included (common when promotions are squashed). Never
  round `unclear` up to `released`; list it in Gaps.
- `reverted` — see §4. Excluded from Shipped, listed in its own section.

**Features.** Group items into features so a reader sees what shipped,
not a list of PRs. The feature key is the first match of:

1. the linked issue key (`ENG-123`), across every repository;
2. the OpenSpec change id;
3. a ticket id in the branch name;
4. otherwise the item stands alone as a one-item feature.

A feature's title comes from the issue or spec, rewritten in plain words.
Its surfaces are the union of its items, its risk the highest item risk,
and its stage the least-promoted stage among its items. When items of one
feature have different stages, the feature is `partially released`: name
which part is released and which is still staged. That is the most
important thing a release reader needs to see.

Feature ids are `F-<n>`, stable within one rundown.

## 6. Write manual test cases

Every feature with `web`, `mobile`, `api`, or `cli` user-visible behavior
gets at least one test case. Features without manual coverage
(refactors, CI, docs) say why and name the automated checks that cover
them. Reverted items get no test case.

Write cases for an agent that has never seen the code:

- Derive steps from spec scenarios first, then issue acceptance criteria,
  then the PR test plan, then the diff. Mark diff-only cases `Inferred`.
- One observable action per step, each with an expected result the tester
  can see on screen or in a response. No "verify it works".
- Name the entry point: route path, screen name, deep link, endpoint, or
  command. Use placeholders such as `<base-url>` and `<test-user>`; never
  write real credentials, tokens, customer data, or production URLs that
  the project does not already document.
- Set `Environment` to the base whose deployment shows the change: the
  release branch for `released` and `hotfix`, the furthest base reached
  for `staged`. A `partially released` feature gets one case per stage
  whose behavior differs, or a single case on the earlier base.
- State preconditions: role or account type, seed data, feature flags,
  platform (iOS/Android/desktop/mobile web), app build.
- Add at least one negative or edge case for `high`-risk features
  (permission denied, invalid input, empty state, retry after failure).
- Tag dimensions the QA agents judge: `functional`, `view`, `business`.
- Add cleanup steps when a case creates or changes data.
- Order cases by environment (release branch first), then risk, then
  surface.

Case ids are `RD-<n>`, stable within one rundown.

## 7. Markdown format (agent copy)

```md
---
rundown: 1
window: { since: <iso>, until: <iso>, timezone: <zone> }
generated: <iso>
repos:
  - name: <name>
    remote: <owner/repo>
    bases: [{ branch: <dev>, head: <sha> }, { branch: <main>, head: <sha> }]
release_branch: <main>
counts: { features: <n>, items: <n>, released: <n>, staged: <n>, hotfix: <n>,
          unclear: <n>, reverted: <n>, in_flight: <n>, test_cases: <n>,
          web: <n>, mobile: <n> }
---

# Rundown: <since> → <until> into <dev> → <main>

## How QA agents use this file
web-qa runs every case with `Surface: web`; mobile-qa runs every case with
`Surface: mobile`. Run them in listed order against the deployment for each
case's `Environment`; ask the caller for that URL or build when it is
missing. Report each case id with PASS, BLOCKING, NIT, or UNVERIFIED. A
missing precondition or environment makes the case UNVERIFIED; never
improvise around it.

## Summary
<3–6 bullets: what changed for users, what is released, what still waits>

## Features
### F-1 — <plain title>
- Stage: <released (main) | staged (dev) | partially released: <part> on main, <part> on dev | hotfix (main, missing from dev) | unclear>
- Surface: <surfaces> · Kind: <kind> · Risk: <risk> · Provenance: <Declared|Inferred>
- Impact: <plain sentence>
- Links: <issue>, <spec change>, <release>
- Items:
  - <repo> #<pr> — <title> · merged <iso> into <base> by <author> · Reached: <base> · Detected by: <ancestry|patch|reference> · <url>
- Tests: RD-1, RD-2 | No manual test: <reason>; covered by <checks>

## Promotions
- <repo> #<pr> — <from> → <to> · <iso> · features: F-1, F-3

## Manual test cases
### RD-1 — <short goal>
- Feature: F-1 · Item: <repo> #<pr>
- Surface: web | Platform: <desktop|mobile web|iOS|Android|any>
- Environment: <base>
- Risk: <risk> · Dimensions: functional, view, business · Provenance: <...>
- Entry: `<base-url>/<path>` | <screen> | <deep link>
- Preconditions: <account/role, seed data, flags, build>
- Steps:
  1. <action> → Expected: <observable result>
  2. <action> → Expected: <observable result>
- Edge cases: <negative or empty-state checks>
- Cleanup: <how to revert created data> | none

## Reverted
- <repo> #<pr> — <title> · reverted by #<pr> on <iso>

## In flight (not shipped)
- <repo> #<pr> — <title> · <state> · targets <base>

## Gaps
- <unavailable sources, unclear stages, hotfixes missing from earlier bases, unclear impact, missing preconditions>
```

Keep the field labels exactly as above so QA agents can filter by them.
Omit Promotions when only one base is selected. Keep every other section
and write `- none` when it is empty.

## 8. HTML format (human copy)

One self-contained file: inline CSS, no scripts required, no external
fonts, images, or CDNs, so it opens offline and survives being emailed.
Escape every value taken from PRs, issues, or commits.

- Header: window with absolute dates, repositories, base branches in
  promotion order, generated time.
- Headline numbers: features released, features waiting on an earlier
  branch, test cases, high-risk features.
- "What changed" first: a short plain-language summary grouped by
  product area or user type, not by repository internals.
- "Released" and "Waiting to release" sections, one card per feature:
  plain title, impact sentence, kind/risk/stage badges, the repositories
  involved, links to the PRs, issue, and spec. A partially released
  feature appears under Released with a visible note saying which part
  still waits.
- A callout for hotfixes missing from an earlier branch and for features
  whose stage is unclear.
- "What we will verify": a table of test cases (id, goal, feature,
  surface, environment, risk, status `Not run yet`). Steps stay in the
  Markdown file.
- Promotions, Reverted, In flight, and Gaps collapsed with `<details>`.
- Readable at phone width; respects `prefers-color-scheme`; semantic
  headings; sufficient contrast; badges never rely on color alone.

Avoid jargon (SHA, rebase, cherry-pick, first-parent, refactor) in prose;
say what changed, who notices it, and whether it is live yet.

## Output

- Write both files under `reports/rundown/` of the current repository, or
  of the current directory when the rundown spans several repositories.
  Slug: `<since>_<until>`, plus `-<repo>` for single-repository runs, plus
  `-<base>` per selected base when it is not only the default branch.
- Never overwrite an existing rundown for the same slug without asking;
  offer a suffixed name instead.
- Reply with both paths, the counts, partially released and high-risk
  features, hotfixes missing from earlier bases, and the gaps. Do not
  paste the full rundown into the reply.

## Evidence

Every item cites its source (PR URL, commit SHA, spec path, issue key)
and every stage names the method that decided it. The front matter
records each base's HEAD SHA so a later reader knows exactly what the
rundown covered.

## Failure behavior

- A repository or base that cannot be read is listed in Gaps; the
  rundown continues with the others.
- An empty window produces a rundown that says nothing shipped, never an
  invented summary.
- A stage that no method confirms is `unclear`, never `released`.
- Never checkout, reset, stash, commit, push, or edit files in the
  inspected repositories. Network fetches only with permission.
- Redact anything that looks like a secret, token, personal data, or
  customer record before writing either file.
