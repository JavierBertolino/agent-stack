---
name: rundown
description: Summarize which features shipped across one or more repositories in a time window and base branches (e.g. "/rundown last 7 days into main,dev"), cross-checked against the issue tracker. Writes an agent-facing Markdown rundown with manual test cases for web-qa and mobile-qa, plus a self-contained HTML page for humans.
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

It answers four questions: which features shipped, whether each one is in
production or still in staging, whether the issue tracker agrees, and how
to verify them.

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
4. Map each base to an environment. Default: `main`/`master` →
   `production`; `dev`/`develop`/`development` → `staging`; a `staging`
   branch → `staging` (and then `dev`/`develop` → `development`);
   `release/*` → `production` when it is the last base, otherwise
   `staging`. A mapping the user states in words wins. Show the mapping
   when restating the window.

Record each base's HEAD SHA at the time of the rundown. Stages in §5
describe the branches as they are now, not as they were at `until`.

## 4. Collect evidence (per repository and base, read-only)

"Shipped" means merged into a selected base inside the window. Merged
into a base is treated as live in that base's environment (§3). Deploy
workflow runs and release tags are extra evidence: a failed or missing one
for a `production` base goes in Gaps and does not change the stage.

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
4. Tracker issues. Detect the tracker from the connected MCP servers
   (Linear, Jira, Trello). Resolve every key found in PR titles, bodies,
   branch names, and commit messages, matching keys without regard to
   case (`hor-18` is `HOR-18`). Also list issues that reached a done state
   inside the window for the team or project that owns the repository
   (ask once when several match). Read title, status, parent,
   sub-issues, and acceptance criteria. Never update an issue from this
   skill. With no tracker connected, group by branch ticket id only and
   say so in Gaps.
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

**Same change, one item.** A change that lands more than once (a
backport, a cherry-pick, a PR merged into two bases, or one branch in
several worktrees) is one item. Match by the same issue key plus an
equivalent patch (`git cherry`), or a PR body that names the other PR.
Keep the earliest merge as the item and list the others under
`Also landed`.

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

- `released` — reached the release branch (production).
- `staged` — on an earlier base only (staging), and no promotion into the next
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

1. the linked issue key (`ENG-123`), rolled up to its top-level parent
   when the tracker has one (a parent and its sub-issues are one
   feature), across every repository;
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

## 6. Cross-check the tracker

Skip when no tracker was read. Compare the issues from §4 with the
features from §5 and report each disagreement in the Tracker cross-check
section. A finding is a fact to review: never change an issue, and never
hide or add a feature to make the two agree.

- `done, not merged`: an issue done in the window with no merged PR on
  the selected bases. Say where its PRs are instead: merged before the
  window, merged to an unselected branch or repository, still open, or
  none found.
- `merged, no issue`: an item with no issue key. It ships as its own
  feature and is listed as untracked work.
- `status behind`: the tracker says Todo, In Progress, or In Review for a
  feature that is in production.
- `status ahead`: the tracker says Done or Released for a feature that is
  only in staging or `unclear`. The stage is the truth about the code; the
  tracker is the team's claim.
- `parts missing`: a parent issue is done but a sub-issue has no merged
  PR.

## 7. Write manual test cases

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
- One case per feature and client surface, never per repository or PR. A
  feature spanning `mobile` and `servers` gets one end-to-end case on the
  client the user touches; list the repositories and items it exercises
  in `Covers`, and name the repository in a step when the tester needs to
  know which part it checks. Add both a web and a mobile case only when
  both clients changed.
- Merge cases that exercise the same screen and action for different
  features into one case that lists every feature. Never test one
  behavior twice.
- Set `Environment` to the environment and its branch, such as
  `staging (dev)` or `production (main)`. Set `Mutates data` to `yes` when
  any step creates, changes, or deletes data. Cases that mutate data run
  in staging, also for features already in production, because staging
  holds everything released unless a hotfix is missing from it. In
  production run only `Mutates data: no` cases, as read-only checks. A
  feature that exists only in production and needs a data-changing case
  gets `Environment: production (needs approval)`: QA stops before the
  first data-changing step and reports UNVERIFIED unless the caller
  approved it. A `partially released` feature gets a case per
  environment whose behavior differs, or one case in staging.
- State preconditions: role or account type, seed data, feature flags,
  platform (iOS/Android/desktop/mobile web), app build.
- Add at least one negative or edge case for `high`-risk features
  (permission denied, invalid input, empty state, retry after failure).
- Tag dimensions the QA agents judge: `functional`, `view`, `business`.
- Add cleanup steps when a case creates or changes data.
- Order cases by environment (production first), then risk, then
  surface.

Case ids are `RD-<n>`, stable within one rundown.

## 8. Markdown format (agent copy)

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
environments: { <dev>: staging, <main>: production }
tracker: <linear|jira|trello|none>
counts: { features: <n>, items: <n>, released: <n>, staged: <n>, hotfix: <n>,
          unclear: <n>, reverted: <n>, in_flight: <n>, untracked: <n>,
          tracker_findings: <n>, test_cases: <n>, web: <n>, mobile: <n> }
---

# Rundown: <since> → <until> into <dev> → <main>

## How QA agents use this file
web-qa runs every case with `Surface: web`; mobile-qa runs every case with
`Surface: mobile`. Run them in listed order against the deployment for each
case's `Environment`; ask the caller for that URL or build when it is
missing. Production cases are read-only: stop before any step that would
create, change, or delete data and report UNVERIFIED. Report each case id
with PASS, BLOCKING, NIT, or UNVERIFIED. A missing precondition or
environment makes the case UNVERIFIED; never improvise around it.

## Summary
<3–6 bullets: what changed for users, what is released, what still waits>

## Features
### F-1 — <plain title>
- Stage: <released (production: main) | staged (staging: dev) | partially released: <part> in production, <part> in staging | hotfix (production, missing from staging) | unclear>
- Surface: <surfaces> · Kind: <kind> · Risk: <risk> · Provenance: <Declared|Inferred>
- Impact: <plain sentence>
- Tracker: <key> <status>, parent <key> | none
- Links: <issue>, <spec change>, <release>
- Items:
  - <repo> #<pr> — <title> · merged <iso> into <base> by <author> · Reached: <base> · Detected by: <ancestry|patch|reference> · Also landed: <base> #<pr> | none · <url>
- Tests: RD-1, RD-2 | No manual test: <reason>; covered by <checks>

## Promotions
- <repo> #<pr> — <from> → <to> · <iso> · features: F-1, F-3

## Manual test cases
### RD-1 — <short goal>
- Feature: F-1 · Covers: <repo> #<pr>, <repo> #<pr>
- Surface: web | Platform: <desktop|mobile web|iOS|Android|any>
- Environment: <staging (dev) | production (main) | production (needs approval)> · Mutates data: <yes|no>
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

## Tracker cross-check
- <done, not merged | merged, no issue | status behind | status ahead | parts missing> — <key> <title> · <detail>

## In flight (not shipped)
- <repo> #<pr> — <title> · <state> · targets <base>

## Gaps
- <unavailable sources, unclear stages, hotfixes missing from earlier bases, unclear impact, missing preconditions>
```

Keep the field labels exactly as above so QA agents can filter by them.
Omit Promotions when only one base is selected. Keep every other section
and write `- none` when it is empty.

## 9. HTML format (human copy)

One self-contained file: inline CSS, no scripts required, no external
fonts, images, or CDNs, so it opens offline and survives being emailed.
Escape every value taken from PRs, issues, or commits.

- Header: window with absolute dates, repositories, base branches in
  promotion order, generated time.
- Headline numbers: features in production, features in staging, tracker
  findings, test cases, high-risk features.
- "What changed" first: a short plain-language summary grouped by
  product area or user type, not by repository internals.
- "In production" and "In staging" sections, one card per feature: plain
  title, impact sentence, kind/risk/stage badges, the tracker status, the
  repositories involved, links to the PRs, issue, and spec. A partially
  released feature appears under In production with a visible note saying
  which part is still in staging.
- A callout for hotfixes missing from an earlier branch, features whose
  stage is unclear, and tracker findings (such as a ticket marked Done
  for work that is only in staging). Collapse the tracker section when
  there are none.
- "What we will verify": a table of test cases (id, goal, feature,
  surface, environment, risk, status `Not run yet`). Steps stay in the
  Markdown file.
- Promotions, Reverted, In flight, and Gaps collapsed with `<details>`.
- Readable at phone width; respects `prefers-color-scheme`; semantic
  headings; sufficient contrast; badges never rely on color alone.

Avoid jargon (SHA, rebase, cherry-pick, first-parent, refactor) in prose;
say what changed, who notices it, and whether it is live in production
yet.

## Output

- Write both files under `reports/rundown/` of the current repository, or
  of the current directory when the rundown spans several repositories.
  Slug: `<since>_<until>`, plus `-<repo>` for single-repository runs, plus
  `-<base>` per selected base when it is not only the default branch.
- Never overwrite an existing rundown for the same slug without asking;
  offer a suffixed name instead.
- Reply with both paths, the counts, partially released and high-risk
  features, hotfixes missing from earlier bases, tracker findings, and
  the gaps. Do not
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
  inspected repositories, and never write to the issue tracker. Network
  fetches only with permission.
- Redact anything that looks like a secret, token, personal data, or
  customer record before writing either file.
