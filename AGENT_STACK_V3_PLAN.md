# Agent Stack v3: Project-aware agents, skills, and governed delivery

Status: proposed implementation plan, not an implemented release.
Reviewed: 2026-09-07.
Repository: JavierBertolino/agent-stack.
Reviewed commit: 57769549c848bd1a69bccc5f123a606b4854c76f.
Review method: static inspection of the repository tree, role prompts, documentation, installer sections, and current upstream documentation. No installation or end-to-end agent execution was performed. No repository changes were pushed.

## 1. Product intent

Agent Stack installs a project-aware delivery workflow into an existing repository. A resolver turns a Linear issue or direct request into a scoped change, loads the relevant skills and project guidance, delegates user-facing design when needed, prepares OpenSpec artifacts, optionally publishes a specification PR, and delegates implementation to a developer. Verification and UI review precede delivery.

Agent Stack also helps a project author and maintain UX_AGENTS.md and UI_AGENTS.md from its existing instructions, documentation, and implementation evidence. These are project governance documents, not additional autonomous agents.

Keep four delivery roles: resolver, designer, developer, and design-qa. Add capabilities through skills before adding roles. Use the host's delegation and permission mechanisms rather than building another execution service.

The resolver starts from an explicit issue/request. A polling service, webhook listener, distributed queue, or always-running worker is not part of this iteration.

## 2. What the existing repository already gets right

Preserve platform-neutral role sources, the four-role separation, conditional UI routing, implementation worktrees, task-level verification, structured reports, protected human-owned files, generated-file hashes, scoped PR delivery, preservation of existing Linear assignees, and the distinction between an open PR and completed work.

Preserve Herdr support, but move its execution details out of the neutral resolver role and into an optional delegation adapter.

## 3. Findings from the current implementation

### F1: Product context is deliberately excluded from useful sources

Evidence: `.agent-stack/roles/resolver.md`, section 0, restricts AGENTS.md/CLAUDE.md to non-product context and permits UX/UI product context only from UX_AGENTS.md and UI_AGENTS.md. Other roles also reject additional project design documents.

Impact: project intent already documented in AGENTS.md or an explicitly linked product/design document can be ignored. A generated guide cannot safely become the only source while the authoritative material is excluded.

Change: read applicable repository instructions and follow their explicit references. Apply existing UX/UI governance as focused guidance, not as a reason to discard upstream instructions. Preserve scope and instruction authority; flag genuine contradictions instead of silently choosing a source.

### F2: Governance setup creates placeholders, not derived guidance

Evidence: `scripts/setup-agent-stack.sh`, functions `write_embedded_ux_agents`, `write_embedded_ui_agents`, and `ensure_scaffolds`.

Impact: installation can leave users with correctly named but practically empty files. File existence does not establish usable governance.

Change: separate deterministic installation from an agent-assisted governance bootstrap. Report whether governance is missing, scaffold-only, draft, reviewed, or stale.

### F3: Skills are not a first-class installed capability

Evidence: the reviewed repository tree has no skill source directory. The developer explicitly reads `.opencode/skills/openspec-apply-change/SKILL.md`. `render_claude` emits restricted tool lists without Skill access and without a skills preload field.

Impact: the workflow relies on a platform-specific dependency path without a portable skill installation/discovery contract. A role prompt saying to use a skill is not enough.

Change: introduce a skills registry, platform-specific discovery rendering, dependency checks, and skill-use evidence. Reuse installed OpenSpec skills rather than maintaining an independent imitation.

### F4: Specification publication conflicts with the requested workflow

Evidence: README.md and resolver closeout require SPECS_REPOSITORY. Installer init, sync, and check call `require_specs_repository`. Publication happens after implementation.

Impact: local-only use is blocked, and a spec PR is not available before implementation.

Change: support explicit local and mirror modes. In mirror mode, create/update the spec PR after specification readiness and before implementation. Refresh the same publication after verification.

### F5: Neutral behavior contains platform-specific assumptions

Evidence: the resolver ledger lives under `.opencode/pipeline-state`; the developer hardcodes an OpenCode skill path; the neutral resolver contains detailed Herdr commands.

Change: move run state to `.agent-stack/runs`; resolve skill locations through adapters; keep Herdr dispatch in a selected adapter.

### F6: Documentation describes gates but does not itself enforce them

Evidence: workflow gates, retry counting, and skill pause overrides are expressed in prompts. OpenCode's resolver permissions include broad Git and GitHub patterns. Claude's designer can Write without the same native path restriction rendered for OpenCode. Codex's designer receives workspace-write.

Impact: a neutral write boundary is not equivalent to an enforced boundary on each runtime. For example, `git -C *` is not a read-only permission.

Change: distinguish policy from enforcement. Use supported permissions, scoped write tools/hooks where available, and fail-closed capability checks for required boundaries. Do not claim equivalent protection when the adapter cannot provide it. Never let a skill or handoff override authorization, security, destructive-action, or verification requirements.

### F7: Updating the kit is not the same as updating installed role sources

Evidence: `ensure_role_sources` uses copy-if-missing; platform mirrors are rendered from the consuming project's role files.

Impact: preserving local edits is desirable, but updating the kit and running sync need not propagate revised default roles.

Change: make ownership explicit. Add an upgrade path with recorded source versions/hashes and a three-way comparison. Update unchanged managed sources, preserve user changes, and surface conflicts. Do not make sync destructively replace project customizations.

### F8: Distribution and test coverage need explicit contracts

Evidence: the tree contains both large self-contained setup entrypoints plus separate role sources; no tests directory or CI workflow is present in the reviewed tree.

Change: author neutral sources once, generate standalone distribution output reproducibly, and test installer behavior and artifact consistency. Runtime integration tests are separate from file-rendering tests.

## 4. Architectural boundaries

| Layer | Question it answers | Owned content |
| --- | --- | --- |
| Agent role | Who is responsible? | Responsibility, allowed outputs, delegation/report contract |
| Skill | How is this action performed? | Procedure, dependencies, evidence, failure behavior |
| Project governance | What is correct for this product? | Audience, language, domain constraints, UX/UI rules |
| Runtime adapter | How is it executed here? | Agent format, skill discovery, tools, permissions, delegation |
| Run state | What actually happened? | Stage, inputs, artifacts, checks, external IDs, next action |

Skills are procedures, not credentials or sandboxes. MCP/tool connections provide access; runtime authorization controls that access. Installing a skill must not implicitly authorize all actions it describes.

## 5. Proposed delivery flow

```text
Explicit Linear issue / direct request
  -> preflight dependencies, repository boundaries, and authorizations
  -> intake + scoped repository context
  -> decide UI/UX impact and record the reason
  -> create/resume OpenSpec change and initial proposal
  -> designer proposal when user-facing behavior is affected
  -> finalize required OpenSpec artifacts and verification tasks
  -> create/update specs PR when mirror mode is configured
  -> developer implements in the supplied worktree
  -> verify scoped changes and task evidence
  -> design-qa reviews UI changes using concrete evidence
  -> refresh specification publication when configured
  -> publish implementation PR(s) and cross-link artifacts
  -> move Linear issue to the configured review/PR state
  -> record awaiting_merge and stop
```

Merge observation and archive/completion are a separate invocation, hook, or existing project process. Do not imply the resolver continues observing after its session ends. Default archive timing should be after verified merge; make alternative project policy explicit.

Do not require routine human approval of every completed specification. Resolve genuine blockers and use the configured publication/authorization policy. A spec PR can remain open while implementation proceeds unless the project explicitly requires its approval.

A backend-heavy ticket still needs design routing when it changes a screen, user workflow, terminology, interaction, accessible behavior, or visible state. Pure internal changes skip designer and design-qa with a recorded reason.

## 6. Skill catalog and selection

These are proposed logical names, not claims that these skills currently exist.

| Skill | Primary consumer | Result |
| --- | --- | --- |
| project-context | All roles | Scoped source map, applicable instructions, evidence and gaps |
| linear-workflow | Resolver | Normalized issue context and verified tracking updates |
| governance-bootstrap | Setup context | Proposed UX/UI governance and source provenance |
| openspec-workflow | Resolver | Ready artifacts through installed OpenSpec procedures |
| ux-design | Designer | User flow, states, copy constraints, component reuse, acceptance criteria |
| implementation | Developer | Scoped implementation using OpenSpec apply and applicable project skills |
| ui-review | Design QA | Evidence-based PASS, BLOCKING, or UNVERIFIED report |
| git-delivery | Resolver | Safe worktrees, specification publication, implementation PRs, cross-links |

Use additional project skills by task relevance: framework conventions, backend/API patterns, accessibility, testing, migrations, or security review. Do not preload every available skill into every agent.

Mandatory stage skills must be loaded before the corresponding action. Optional/domain skills are selected from their declared descriptions and scope. Record skill name, resolved path/source, version or content hash, and why it was used. Missing mandatory dependencies block the relevant stage; never pretend to execute a missing skill.

Keep upstream OpenSpec skills upstream-owned. The local OpenSpec integration should discover the installed capabilities and artifact graph, select the appropriate installed procedure, and add only Agent Stack's tracking/handoff requirements. Validate the supported version/profile during preflight.

### Platform rendering

- OpenCode: render supported skill permissions and discover skills through supported locations. Do not hardcode .opencode paths inside neutral roles.
- Claude Code: use the documented skills preload field for required small procedures where appropriate; retain Skill access for on-demand procedures. A preload list is not an access-control list.
- Codex: support the documented .agents/skills discovery model and optional runtime metadata. Test the actual configured subagent/delegation behavior independently.
- Cursor: verify skill discovery and subagent capabilities against the supported version and test the rendered output. Do not assume its agent/rule formats are interchangeable.

Avoid installing duplicate same-name skills into every discovery root visible to one host. Use an explicit manifest and collision detection, not search-order guesses. Ensure installed guidance is available inside fresh worktrees; uncommitted setup files in the original checkout will not magically appear there.

## 7. Governance bootstrap

Keep the existing canonical names UX_AGENTS.md and UI_AGENTS.md. Support singular legacy names only through deliberate discovery/migration; do not create competing copies.

### Inputs

Read applicable AGENTS.md, CLAUDE.md, existing UX/UI governance, README material relevant to the product, and local documents explicitly referenced by these sources or selected in configuration. Inspect representative components, tokens/styles, routes/flows, and tests to identify implemented patterns. Do not indiscriminately ingest the entire repository.

### Separate evidence from authority

Every derived statement must be classified as one of:

- Declared: supported by an authoritative project instruction or approved document.
- Observed: present in implementation, but not automatically a mandatory product rule.
- Proposed: a recommendation requiring project adoption.
- Unknown/conflicting: unresolved; retain the gap and source references.

Existing code can contain defects and outdated decisions. Never promote an observed component or color into mandatory governance merely because it appears frequently.

### Outputs

UX_AGENTS.md should describe product purpose, audience, principal jobs, vocabulary/language, flow principles, information hierarchy, errors/recovery, permission-sensitive behavior, and UX acceptance criteria.

UI_AGENTS.md should describe existing component and token sources, layout/density, typography, semantic color use, responsive behavior, interaction states, accessibility expectations, component reuse, and required visual evidence.

Store compact provenance in `.agent-stack/context/manifest.json`: source paths and hashes, section references, review status, and generation version. Do not store secrets or wholesale copies of private tickets there.

### Lifecycle

1. Installer creates only missing scaffolds and installs the bootstrap procedure.
2. An explicitly selected host executes the bootstrap skill; without a host, setup prints a precise next command and reports governance as scaffold-only.
3. Bootstrap writes a draft or proposed diff; it does not silently overwrite human-owned guides.
4. Existing rules remain authoritative while drafts await review.
5. Subsequent refreshes compare source hashes and propose targeted changes. They do not turn every ticket into a governance rewrite.

The delivery designer keeps its normal ux.md-only boundary. Governance bootstrap runs in a separate setup context with explicit permission to propose the guide files.

## 8. OpenSpec contract

Use the installed CLI's artifact graph and instructions rather than assuming that every profile has an identical command set or artifact list. OpenSpec's documented structure distinguishes current behavior under openspec/specs from proposed changes under openspec/changes, including delta specifications.

Creating ux.md alone does not establish a dependency in that graph. For the first iteration, make design readiness an explicit Agent Stack gate and pass ux.md by absolute path in every applicable handoff. Add a tested custom OpenSpec schema later if graph-level enforcement is needed. Do not silently replace a project's schema.

Before implementation, require the configured OpenSpec artifacts, acceptance criteria, concrete task verification, and a design artifact for UI work. Do not equate artifact completion with successful implementation verification.

## 9. Optional specification publication

Proposed configuration:

```ini
SPECS_MODE=local
SPECS_REPOSITORY=
SPECS_REPOSITORY_BASE_BRANCH=main
SPECS_PUBLISH_STAGE=before-implementation
SPECS_MERGE_GATE=none
ARCHIVE_STAGE=after-merge
```

`local` means OpenSpec remains in the code repository and no external spec publication is attempted. `mirror` requires an explicitly configured repository and publication authorization; it creates/updates a PR containing the ready specification before developer delegation.

For this iteration, the code repository's OpenSpec artifacts remain authoritative; the central repository is a traceable publication mirror. A truly authoritative central spec repository needs a separate design for multi-repo dependency and synchronization rules.

Namespace mirrored changes by source repository and change identity, for example `projects/<owner>/<repo>/changes/<issue-id>-<slug>/`. Record source repository, branch, change ID, artifact hash, and available commit references. Distinguish a proposed/implemented/merged lifecycle state so an unmerged proposal is not presented as deployed truth.

Reuse the same branch/PR on retry. Update publication after verified spec amendments. Cross-link the issue, spec PR, and implementation PRs. A later source revision must invalidate or refresh publication evidence. In mirror mode, failure is a publication blocker, not a silent switch to local mode.

## 10. Handoffs, evidence, and resumability

Use a versioned contract shared by the four roles. Required fields:

- Run/change/issue identity and current phase.
- Absolute worktree roots, repository IDs, base refs/SHAs, and allowed output scope.
- Artifact paths and hashes, acceptance criteria, explicit exclusions.
- Applicable governance sources and unresolved gaps.
- Required and selected skills.
- Verification plan and any authorized delivery actions.
- Corrective-round budget and expected report schema.

Reports must include status, outputs, files changed, skills used, commands and working directories, results, evidence paths, assumptions, blockers, and proposed next action. Checks should identify the code revision or diff they validate. A command string without an observed result is not evidence.

Use `.agent-stack/runs/<run-id>/state.json` plus append-only events and evidence. The resolver is the sole state writer. Validate transitions and record external side effects immediately, including issue updates and created PR IDs. Use a run/issue lock to prevent concurrent duplicate delivery.

On resume, re-read external state and verify artifact/code hashes. Do not trust an old PASS after the implementation changed. Store run metadata locally/ignored by default; publish only the approved summary and artifacts.

Budget exhaustion results in a blocked or partial outcome, not permission to ship failed safety, correctness, or required verification gates. Make corrective budgets configurable and actually read them instead of leaving hardcoded prompt values.

## 11. QA boundaries

Keep design-qa independent from implementation. Its current UNVERIFIED verdict is useful and should be preserved.

Static file review cannot establish every responsive, keyboard, focus, or interaction property. Supply browser/test evidence generated by an authorized process, or provide a carefully scoped browser capability. Keep tests against isolated/local data where practical; read-only source access does not make browser actions harmless.

Separate required checks from optional polish. Missing required visual evidence blocks a full PASS; missing optional evidence is reported without invented results. Backend-only changes still require their implementation checks and any configured risk-based review; do not introduce unconditional extra agents for every ticket.

## 12. Suggested repository organization

```text
.agent-stack/
  roles/                         # Small platform-neutral role contracts
  skills/                        # Canonical skill source folders
  contracts/                     # Handoff/report/run JSON schemas
  templates/
    UX_AGENTS.md
    UI_AGENTS.md
  defaults.conf
adapters/
  opencode/
  claude/
  codex/
  cursor/
  herdr/
scripts/
  setup-agent-stack.sh            # Installation entrypoint
  build-installer.sh             # Builds standalone distribution
  doctor.sh                     # Dependencies, drift, capabilities
  upgrade-agent-stack.sh         # Safe source-version migration
  validate-contracts.*           # Implementation language chosen locally
setup.sh                         # Generated standalone distribution
AGENTS.md                        # Rules for agents developing Agent Stack itself
docs/
  PRODUCT_INTENT.md
  AGENT_PIPELINE.md
  SKILLS.md
  GOVERNANCE_BOOTSTRAP.md
  ADAPTER_CAPABILITIES.md
tests/
  fixtures/
  installer/
  contracts/
  evals/
.github/workflows/ci.yml
```

This is a proposed layout, not a requirement to rewrite everything at once or switch languages. Retain the POSIX installation interface; extract the large implementation only as needed. The repository's own AGENTS.md should explain that generated consuming-project governance is not this kit's product policy.

## 13. Agency Agents: borrow selectively

Useful references are its orchestrator's handoff/state/evidence discipline and the UI designer's component, token, and developer-handoff focus. Its conversion/install separation is also a useful distribution pattern.

Do not import the entire roster or treat personality prose as runtime functionality. Do not add another PM/architect hierarchy over the resolver and OpenSpec. Avoid inheriting unrelated aesthetic defaults or theme requirements. Do not import a workflow that marks a task complete before verification.

Prefer extracting narrowly scoped, source-attributed procedures into the existing four-role design. If source files are actually copied later, review the repository's license and preserve the applicable notices.

## 14. Implementation sequence

### PR 1: Align behavior and documentation

Update resolver/designer/developer/design-qa context rules. Add product intent for Agent Stack. Introduce explicit local/mirror publication policy and correct before-implementation ordering. Move ledger references to .agent-stack. Remove blanket skill-pause override language; preserve routine no-review-gate behavior without weakening safeguards. Fix the generic designer's language-specific fallback headings.

Acceptance: a local-mode installation does not require a spec repository; referenced AGENTS.md product guidance reaches designer/developer; backend-only work skips design; UI work cannot reach implementation without design readiness.

### PR 2: Make skills and governance real capabilities

Add the canonical skill sources, dependency manifest, host adapters, doctor checks, and bootstrap skill. Resolve installed OpenSpec capabilities rather than hardcoding one host's path. Add structured handoffs and skill-use reporting. Ensure role/skill discovery works in fresh worktrees.

Acceptance: each supported runtime loads the intended mandatory skills; missing required skills produce a truthful blocker; scaffold-only governance is detected; refresh proposes changes while preserving reviewed files; observed code patterns are not mislabeled as approved policy.

### PR 3: Harden delivery and upgrades

Add validated run state, resumable publication, policy-aware permissions, safe upgrade behavior, generated standalone builds, fixture tests, and CI. Test the host compatibility matrix separately from snapshots.

Acceptance: retries reuse branches and PRs; failed publication remains visible; changed code invalidates stale verification; existing human edits survive upgrades; cancelled setup does not falsely claim no filesystem changes if scaffolding was already created; standalone and checkout installations produce equivalent outputs.

## 15. Minimum evaluation scenarios

1. Backend-only Linear issue: no designer/QA delegation; OpenSpec and tests still required.
2. User-facing ticket whose product brief exists only in AGENTS.md and a linked document: correct context reaches the proposal.
3. Repository without guides: no invented users, design tokens, or business rules; bootstrap produces a clearly labeled draft.
4. Conflicting declared guidance and existing code: conflict is reported; code does not silently become policy.
5. Local specs mode: successful workflow without an external specs repository.
6. Mirror mode: a spec PR precedes coding, and final updates reuse that PR.
7. Missing OpenSpec skill or runtime capability: no false claim of readiness.
8. Claude subagent skill loading: mandatory preload and on-demand selection both work as configured.
9. Fresh Git worktree: project agents, skills, and governance are available and resolve correctly.
10. Interrupted run after PR creation: resume discovers the existing PR instead of duplicating it.
11. UI evidence unavailable: UNVERIFIED, not an invented PASS.
12. Failed tests or exhausted budget: blocked/partial outcome, not an automatic ship-as-is.
13. Existing customized installed role: upgrade preserves it and surfaces a merge conflict.
14. A hostile instruction embedded in a ticket: treated as task data, not authority to bypass policy or leak repository content.
15. Base branch is another feature branch: implementation PR retains the recorded stacked base.

## 16. Source map

Repository findings refer to commit 57769549c848bd1a69bccc5f123a606b4854c76f. Relevant files: README.md, docs/AGENT_PIPELINE.md, .agent-stack/README.md, .agent-stack/roles/*.md, .agent-stack/defaults.conf, and scripts/setup-agent-stack.sh (especially render_opencode, render_claude, render_codex, ensure_role_sources, ensure_scaffolds, and command dispatch).

Primary external references consulted on 2026-09-07:

- Agent Skills format and progressive loading: `https://agentskills.io/specification`
- OpenCode skill discovery and permissions: `https://opencode.ai/docs/skills/`
- Claude Code subagent skills, tools, and preload semantics: `https://code.claude.com/docs/en/sub-agents`
- Codex skill discovery: `https://developers.openai.com/codex/skills/` (redirected to the current official skills documentation).
- OpenSpec structure and workflow: `https://github.com/Fission-AI/OpenSpec/blob/main/docs/getting-started.md`
- Agency Agents orchestration: `https://github.com/msitarzewski/agency-agents/blob/main/specialized/agents-orchestrator.md`
- Agency Agents UI guidance: `https://github.com/msitarzewski/agency-agents/blob/main/design/design-ui-designer.md`
- Agency Agents UX architecture: `https://github.com/msitarzewski/agency-agents/blob/main/design/design-ux-architect.md`

Compatibility must be pinned and tested during implementation; current documentation alone does not establish runtime compatibility for this repository.
