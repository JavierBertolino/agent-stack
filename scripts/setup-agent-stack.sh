#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=$(pwd)
COMMAND=init
CLAUDE_ONLY=0
SKIP_OPENCODE=0
SKIP_CLAUDE=0
SKIP_CODEX=0
SKIP_CURSOR=0
INSTALL_CODEX_BRIDGE=0
INTERACTIVE_SELECT=0
EXPLICIT_PLATFORM=0
PLATFORMS_ARG=
CONFLICTS=0

# Per-platform enable flags (0 = skip, 1 = render). Resolved later from config
# defaults, CLI flags, or the interactive multiselect menu.
ENABLE_OPENCODE=1
ENABLE_CLAUDE=1
ENABLE_CODEX=1
ENABLE_CURSOR=1

usage() {
  cat <<'EOF'
Usage:
  setup-agent-stack.sh [init|sync|check|adopt|prune] [options]

Commands:
  init       Create missing project guides, config, and generated agents.
  sync       Generate missing or previously-managed platform files.
  check      Check files without changing anything.
  adopt      Create neutral role sources from existing OpenCode agents.
  prune      Remove only stale files recorded as generated.

Options:
  --root PATH                 Target project root. Defaults to the current directory.
  --kit-root PATH             Optional kit directory with role/template overrides.
                              Missing kit files fall back to embedded content.
  --platforms LIST            Comma-separated platforms to configure:
                              opencode, claude, codex, cursor.
  --select                    Force the interactive platform multiselect.
  --claude-only               Only render/check Claude mirrors.
  --skip-opencode             Do not render/check OpenCode agents.
  --skip-claude               Do not render/check Claude agents.
  --skip-codex                Do not render/check Codex files.
  --skip-cursor               Do not render/check Cursor agents.
  --install-codex-bridge      Add the managed guidance block to AGENTS.md.
  -h, --help                  Show this help.

Platforms: running interactively (init/sync) with no platform flag shows a
multiselect menu for OpenCode, Claude Code, Codex, and Cursor. Non-interactive
runs use the ENABLE_* defaults from .agent-stack/config.conf (all on).

Linear MCP: when a platform is enabled, the script registers the connected
Linear MCP server (name/URL from LINEAR_MCP_NAME / LINEAR_MCP_URL) in that
platform's config: opencode.jsonc (OpenCode), .mcp.json (Claude),
.cursor/mcp.json (Cursor), and .codex/config.toml (Codex).

The script never overwrites an existing untracked human-owned file. Use
adopt to import an existing OpenCode prompt into the neutral role source.
EOF
}

die() {
  printf '%s\n' "setup-agent-stack.sh: $*" >&2
  exit 1
}

abspath_dir() {
  CDPATH= cd -- "$1" 2>/dev/null && pwd
}

ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}

copy_if_missing() {
  source_path=$1
  target_path=$2
  [ -e "$target_path" ] && return 0
  [ -f "$source_path" ] || die "missing kit file: $source_path"
  ensure_dir "$(dirname -- "$target_path")"
  cp "$source_path" "$target_path"
  printf 'created %s\n' "$target_path"
}

file_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    cksum "$1" | awk '{print $1 ":" $2}'
  fi
}

get_config() {
  key=$1
  fallback=$2
  if [ ! -f "$CONFIG_FILE" ]; then
    printf '%s\n' "$fallback"
    return 0
  fi

  value=$(awk -F= -v wanted="$key" '
    $1 == wanted {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$CONFIG_FILE")

  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

manifest_hash() {
  relative_path=$1
  [ -f "$MANIFEST_FILE" ] || return 1
  awk -F'|' -v wanted="$relative_path" '$1 == wanted { print $2; found=1; exit } END { exit(found ? 0 : 1) }' "$MANIFEST_FILE"
}

record_manifest() {
  relative_path=$1
  hash=$2
  ensure_dir "$(dirname -- "$MANIFEST_FILE")"
  temporary=$(mktemp "$MANIFEST_FILE.XXXXXX")

  if [ -f "$MANIFEST_FILE" ]; then
    awk -F'|' -v wanted="$relative_path" -v replacement="$hash" '
      BEGIN { found = 0 }
      $1 == wanted {
        if (!found) print wanted "|" replacement
        found = 1
        next
      }
      { print }
      END {
        if (!found) print wanted "|" replacement
      }
    ' "$MANIFEST_FILE" > "$temporary"
  else
    printf '%s\n' "$relative_path|$hash" > "$temporary"
  fi

  mv "$temporary" "$MANIFEST_FILE"
}

relative_path() {
  printf '%s\n' "${1#"$ROOT/"}"
}

install_generated() {
  relative=$1
  temporary=$2
  destination=$ROOT/$relative
  expected_hash=$(file_hash "$temporary")

  if [ -e "$destination" ]; then
    current_hash=$(file_hash "$destination")
    if [ "$current_hash" = "$expected_hash" ]; then
      rm -f "$temporary"
      record_manifest "$relative" "$current_hash"
      return 0
    fi

    recorded_hash=$(manifest_hash "$relative" 2>/dev/null || true)
    if [ -n "$recorded_hash" ] && [ "$current_hash" = "$recorded_hash" ]; then
      ensure_dir "$(dirname -- "$destination")"
      mv "$temporary" "$destination"
      record_manifest "$relative" "$expected_hash"
      printf 'updated %s\n' "$destination"
      return 0
    fi

    rm -f "$temporary"
    printf 'conflict, preserved %s\n' "$destination" >&2
    CONFLICTS=$((CONFLICTS + 1))
    return 0
  fi

  ensure_dir "$(dirname -- "$destination")"
  mv "$temporary" "$destination"
  record_manifest "$relative" "$expected_hash"
  printf 'created %s\n' "$destination"
}

check_generated() {
  relative=$1
  temporary=$2
  destination=$ROOT/$relative

  if [ ! -e "$destination" ]; then
    rm -f "$temporary"
    printf 'missing %s\n' "$destination" >&2
    CONFLICTS=$((CONFLICTS + 1))
    return 0
  fi

  expected_hash=$(file_hash "$temporary")
  current_hash=$(file_hash "$destination")
  rm -f "$temporary"

  if [ "$current_hash" != "$expected_hash" ]; then
    printf 'drift %s\n' "$destination" >&2
    CONFLICTS=$((CONFLICTS + 1))
  fi
}

description_for() {
  case "$1" in
    resolver) printf '%s\n' 'Project-agnostic PO/manager — turns requests into governed OpenSpec changes, delegates UX, UI QA, and implementation, verifies evidence, and synchronizes Linear.' ;;
    designer) printf '%s\n' "Project-agnostic UX designer — produces UX proposals from the current project's UX_AGENTS.md and UI_AGENTS.md guidance. Invoked by resolver." ;;
    design-qa) printf '%s\n' "Project-agnostic UI QA reviewer — performs read-only, adversarial, severity-tagged review from the current project's UX_AGENTS.md and UI_AGENTS.md guidance." ;;
    developer) printf '%s\n' 'Project-agnostic implementer — executes OpenSpec tasks with minimal diffs, follows project UX/UI guidance, verifies each task, and reports evidence. Invoked by resolver.' ;;
    *) die "unknown role: $1" ;;
  esac
}

enable_platform() {
  case "$1" in
    opencode) ENABLE_OPENCODE=1 ;;
    claude|claude-code) ENABLE_CLAUDE=1 ;;
    codex) ENABLE_CODEX=1 ;;
    cursor) ENABLE_CURSOR=1 ;;
    *) die "unknown platform: $1 (use opencode, claude, codex, cursor)" ;;
  esac
}

select_platforms_interactive() {
  [ -t 0 ] || die "--select requires an interactive terminal"

  o=$ENABLE_OPENCODE
  c=$ENABLE_CLAUDE
  x=$ENABLE_CODEX
  r=$ENABLE_CURSOR

  while :; do
    printf '\nSelect platforms to configure (enter number to toggle, Enter to confirm):\n'
    if [ "$o" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  1 %s OpenCode\n' "$m"
    if [ "$c" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  2 %s Claude Code\n' "$m"
    if [ "$x" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  3 %s Codex\n' "$m"
    if [ "$r" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  4 %s Cursor\n' "$m"
    printf '  a) select all   n) select none\n'
    printf '> '
    IFS= read -r choice || { printf '\n'; break; }
    case "$choice" in
      1) [ "$o" = 1 ] && o=0 || o=1 ;;
      2) [ "$c" = 1 ] && c=0 || c=1 ;;
      3) [ "$x" = 1 ] && x=0 || x=1 ;;
      4) [ "$r" = 1 ] && r=0 || r=1 ;;
      a|all) o=1; c=1; x=1; r=1 ;;
      n|none) o=0; c=0; x=0; r=0 ;;
      ''|d|done) break ;;
      *) printf 'choose 1-4, a, n, or Enter\n' ;;
    esac
  done

  ENABLE_OPENCODE=$o
  ENABLE_CLAUDE=$c
  ENABLE_CODEX=$x
  ENABLE_CURSOR=$r
}

resolve_platforms() {
  # Base: ENABLE_* defaults from config.conf (all enabled when unset).
  [ "$(get_config ENABLE_OPENCODE 1)" = 0 ] && ENABLE_OPENCODE=0
  [ "$(get_config ENABLE_CLAUDE 1)" = 0 ] && ENABLE_CLAUDE=0
  [ "$(get_config ENABLE_CODEX 1)" = 0 ] && ENABLE_CODEX=0
  [ "$(get_config ENABLE_CURSOR 1)" = 0 ] && ENABLE_CURSOR=0

  if [ -n "$PLATFORMS_ARG" ]; then
    ENABLE_OPENCODE=0; ENABLE_CLAUDE=0; ENABLE_CODEX=0; ENABLE_CURSOR=0
    oldIFS=$IFS
    IFS=','
    for p in $PLATFORMS_ARG; do
      enable_platform "$p"
    done
    IFS=$oldIFS
    return 0
  fi

  if [ "$CLAUDE_ONLY" = 1 ]; then
    ENABLE_OPENCODE=0; ENABLE_CLAUDE=1; ENABLE_CODEX=0; ENABLE_CURSOR=0
    return 0
  fi

  if [ "$EXPLICIT_PLATFORM" = 1 ]; then
    [ "$SKIP_OPENCODE" = 1 ] && ENABLE_OPENCODE=0
    [ "$SKIP_CLAUDE" = 1 ] && ENABLE_CLAUDE=0
    [ "$SKIP_CODEX" = 1 ] && ENABLE_CODEX=0
    [ "$SKIP_CURSOR" = 1 ] && ENABLE_CURSOR=0
    return 0
  fi

  if [ "$INTERACTIVE_SELECT" = 1 ] || { [ -t 0 ] && { [ "$COMMAND" = init ] || [ "$COMMAND" = sync ]; }; }; then
    select_platforms_interactive
  fi
}

render_opencode() {
  role=$1
  output=$2
  description=$(description_for "$role")

  case "$role" in
    resolver) model=$(get_config OPENCODE_RESOLVER_MODEL 'openai/gpt-5.6-luna'); variant=$(get_config OPENCODE_RESOLVER_VARIANT 'max'); mode='primary'; color='primary' ;;
    designer) model=$(get_config OPENCODE_DESIGNER_MODEL 'openai/gpt-5.6-luna'); variant=$(get_config OPENCODE_DESIGNER_VARIANT 'max'); mode='subagent'; color='accent' ;;
    design-qa) model=$(get_config OPENCODE_DESIGN_QA_MODEL 'openai/gpt-5.6-luna'); variant=$(get_config OPENCODE_DESIGN_QA_VARIANT 'max'); mode='subagent'; color='accent' ;;
    developer) model=$(get_config OPENCODE_DEVELOPER_MODEL 'openrouter/deepseek-v4-pro'); variant=$(get_config OPENCODE_DEVELOPER_VARIANT 'high'); mode='subagent'; color='success' ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf '%s\n' '---'
    printf 'description: %s\n' "$description"
    printf 'model: %s\n' "$model"
    printf 'variant: %s\n' "$variant"
    printf 'mode: %s\n' "$mode"
    printf 'color: %s\n' "$color"
    printf '%s\n' 'permission:'
    case "$role" in
      resolver)
        printf '%s\n' '  edit: allow' '  skill: allow' '  question: allow' '  todowrite: allow' '  bash:' '    "*": ask' '    "openspec *": allow' '    "git status *": allow' '    "git diff *": allow' '    "git log *": allow' '    "git branch *": allow' '    "git checkout *": allow' '    "git worktree *": allow' '  task:' '    "*": deny' '    designer: allow' '    design-qa: allow' '    developer: allow' '    explore: allow'
        ;;
      designer)
        printf '%s\n' '  bash: deny' '  task: deny' '  edit:' '    "*": deny' '    "openspec/changes/**/ux.md": allow'
        ;;
      design-qa)
        printf '%s\n' '  edit: deny' '  bash: deny' '  task: deny'
        ;;
      developer)
        printf '%s\n' '  edit: allow' '  bash: allow' '  skill: allow' '  task: deny'
        ;;
    esac
    printf '%s\n' '---' ''
  } > "$output"

  cat "$ROLE_DIR/$role.md" >> "$output"
}

render_claude() {
  role=$1
  output=$2
  description=$(description_for "$role")

  case "$role" in
    resolver) model=$(get_config CLAUDE_RESOLVER_MODEL 'opus'); tools='' ;;
    designer) model=$(get_config CLAUDE_DESIGNER_MODEL 'opus'); tools='Read, Grep, Glob, Write' ;;
    design-qa) model=$(get_config CLAUDE_DESIGN_QA_MODEL 'opus'); tools='Read, Grep, Glob' ;;
    developer) model=$(get_config CLAUDE_DEVELOPER_MODEL 'sonnet'); tools='Read, Grep, Glob, Edit, Write, Bash' ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf '%s\n' '---' "name: $role" "description: $description" "model: $model"
    [ -n "$tools" ] && printf 'tools: %s\n' "$tools"
    printf '%s\n' '---' ''
  } > "$output"

  cat "$ROLE_DIR/$role.md" >> "$output"
}

render_codex() {
  role=$1
  output=$2
  description=$(description_for "$role")
  sandbox_mode=workspace-write
  if [ "$role" = design-qa ]; then
    sandbox_mode=read-only
  fi

  case "$role" in
    resolver) model=$(get_config CODEX_RESOLVER_MODEL 'gpt-5.6-luna'); effort=$(get_config CODEX_RESOLVER_EFFORT 'xhigh') ;;
    designer) model=$(get_config CODEX_DESIGNER_MODEL 'gpt-5.6-luna'); effort=$(get_config CODEX_DESIGNER_EFFORT 'xhigh') ;;
    design-qa) model=$(get_config CODEX_DESIGN_QA_MODEL 'gpt-5.6-luna'); effort=$(get_config CODEX_DESIGN_QA_EFFORT 'xhigh') ;;
    developer) model=$(get_config CODEX_DEVELOPER_MODEL 'gpt-5.6'); effort=$(get_config CODEX_DEVELOPER_EFFORT 'high') ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf 'name = "%s"\n' "$role"
    printf 'description = "%s"\n' "$description"
    printf 'model = "%s"\n' "$model"
    printf 'model_reasoning_effort = "%s"\n' "$effort"
    printf 'sandbox_mode = "%s"\n' "$sandbox_mode"
    printf '%s\n' 'developer_instructions = """'
    cat "$ROLE_DIR/$role.md"
    printf '%s\n' '"""'
  } > "$output"
}

render_cursor() {
  role=$1
  output=$2
  description=$(description_for "$role")

  case "$role" in
    resolver) model=$(get_config CURSOR_RESOLVER_MODEL 'gpt-5.6-luna'); readonly=false ;;
    designer) model=$(get_config CURSOR_DESIGNER_MODEL 'gpt-5.6-luna'); readonly=false ;;
    design-qa) model=$(get_config CURSOR_DESIGN_QA_MODEL 'gpt-5.6-luna'); readonly=true ;;
    developer) model=$(get_config CURSOR_DEVELOPER_MODEL 'gpt-5.6-terra'); readonly=false ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$role"
    printf 'description: %s\n' "$description"
    printf 'model: %s\n' "$model"
    if [ "$readonly" = true ]; then
      printf '%s\n' 'readonly: true'
    fi
    printf '%s\n' '---' ''
  } > "$output"

  cat "$ROLE_DIR/$role.md" >> "$output"
}

render_config() {
  output=$1
  max_threads=$(get_config CODEX_MAX_CONCURRENT_THREADS 4)
  mcp_name=$(get_config LINEAR_MCP_NAME 'linear')
  mcp_url=$(get_config LINEAR_MCP_URL 'https://mcp.linear.app/mcp')
  {
    printf '%s\n' '# Project-local Codex configuration generated by setup-agent-stack.sh.'
    printf '%s\n' '# This file does not contain credentials or global settings.'
    printf '%s\n' '' '[agents]'
    printf '%s\n' 'enabled = true' "max_concurrent_threads_per_session = $max_threads"
    printf '%s\n' '' "[mcp_servers.$mcp_name]"
    printf '%s\n' "url = \"$mcp_url\""
  } > "$output"
}

render_codex_readme() {
  output=$1
  if [ -f "$KIT_ROOT/.agent-stack/templates/codex.README.md" ]; then
    cat "$KIT_ROOT/.agent-stack/templates/codex.README.md" > "$output"
  else
    write_embedded_codex_readme "$output"
  fi
}

# --- Embedded fallback content (for standalone single-file use) ---
# When the kit directory is absent, these writers seed the project with
# the bundled role prompts, guide templates, and defaults.
write_role_source() {
  role=$1
  target=$2
  case "$role" in
    resolver) cat > "$target" <<'ROLE_RESOLVER_EOF'
You are the resolver and delivery manager for the current project. You own
requirements, OpenSpec artifacts, delegation, evidence, and Linear
synchronization. You never write implementation code yourself. You specify,
delegate, review, and close.

You are the only agent that communicates with the user. Subagents return
structured reports to you and never reply to the user directly.

## 0. Project context and local guidance

Before making product or implementation decisions:

1. Read repository-level `AGENTS.md` and `CLAUDE.md` only for safety, tool,
   repository, and financial-control instructions; never use them as a UX/UI
   product brief.
2. Identify repositories, branch policy, test commands, and artifact
   conventions from the request and existing project structure.
3. For any UX or UI work, discover and read only the nearest applicable
   `UX_AGENTS.md` and `UI_AGENTS.md`. These files are project-specific policy;
   never assume their language, brand, components, roles, or workflows.
4. Do not search for or hardcode additional product-specific guideline files.
   If a UX/UI guide is absent, do not invent project conventions.

Only `UX_AGENTS.md` and `UI_AGENTS.md` may supply UX/UI product context. Do not
open other project-specific UX/UI audit or guideline documents.
If a project-specific guide is absent, use the request and existing code
patterns, and report the missing guide as a maintainability follow-up when
relevant.

If project instructions conflict, stop and ask the user. Do not silently apply
rules from another project.

## 1. Intake

If given a Linear issue identifier:

1. Resolve it with the connected Linear MCP. Do not hardcode a Linear MCP
   server name; use the connected server and its available tools.
2. Read the issue description and comments only as needed for scope.
3. Record the issue's Linear project name, branch name, repository, acceptance
   criteria, and closeout requirements when available. If the issue has no
   project name, ask the user before creating a Linear document.

If given free-form input, derive a kebab-case change name and ask whether a
Linear issue should be linked. If no issue is linked, skip Linear sync.

## 2. Clarify

Resolve ambiguity with the user before writing specs. Ask all required
questions in one question round. Cover:

- affected repositories or packages;
- whether user-facing UX/UI is touched;
- constraints, deadline, compatibility, and rollout requirements;
- Linear acceptance, project, or closeout requirements not already stated.

If a required answer is missing, stop and ask. Do not start a partial pipeline.

## 3. Branch setup

Identify affected Git repositories and paths from the project instructions and
the request. Do not assume a monorepo or fixed directory names.

For each affected repository:

1. Run `git status --porcelain`.
2. If clean, create the project-approved branch from the current base.
3. If dirty, ask the user once whether to use a worktree, a new branch with
   existing changes, or the current branch.

Use the issue branch name when available; otherwise use the project-approved
fallback or the OpenSpec change name. Record the decision in the delegation
contract. The prompt-level worktree strategy is the active default.

## 4. Specify

1. Create the OpenSpec change:
   ```
   openspec new change "<name>"
   ```
2. Read the artifact graph:
   ```
   openspec status --change "<name>" --json
   ```
3. For each ready artifact, read its instructions and completed dependencies,
   then author it using the schema template.
4. Repeat until all artifacts required for implementation are complete.

Create `.opencode/pipeline-state/<change-name>.log` if it does not exist. The
ledger is append-only and records corrective rounds, evidence, and next action.

### 4.1 Project governance

Every applicable rule from `UX_AGENTS.md` and `UI_AGENTS.md` MUST be reflected
in the relevant UX/UI artifact. Repository-level safety, financial-control,
and security instructions remain binding, but they are not UX/UI context. Never
assume that a rule from another project applies here.

### 4.2 Task verification contract

Every task in `tasks.md` MUST carry a concrete verification line:

```md
- [ ] Implement the primary behavior
  verification: `<project test command>` — expected pass condition
```

The check should run in under five minutes, or name the closest available
typecheck, lint, build, manual, or E2E check. The developer runs it, reports
the command and result, and checks the task only after it passes.

### 4.3 Design traceability block

When `design.md` exists, add this block before `## Context`:

```md
## Traceability

- Linear project: <project name> (`<project id>`)
- Linear team: <team name> (`<team id>`)
- Linear issue: <identifier> (`<issue id>`, <issue URL>)
- Linear cycle: <name or none>
- Linear milestone: <name or none>
- OpenSpec change: <change-name>
- Repositories: <repository paths>
- Branch/worktree: <branch and path>
- Captured at: <ISO-8601 timestamp>
```

Populate project, team, issue, cycle, and milestone values from the connected
Linear MCP. Use `none` for unavailable values; never guess or copy tokens and
secrets. For an unlinked change, use `Linear project: none` and
`Linear issue: none`.

## 5. Route UX and UI work

Treat a change as UI/UX work when it changes a user-facing screen, flow, copy,
state, interaction, accessibility behavior, or visual component, even if the
backend work is larger.

For UI/UX work:

1. Read `UX_AGENTS.md` and `UI_AGENTS.md` before delegation.
2. Delegate proposal mode to `designer` before completing `design.md` and
   `tasks.md`.
3. Reference the applicable project-guide sections in the artifacts and tasks.

Pure backend, data, or internal tooling changes skip UX delegation.

## 6. Delegate implementation

Call `developer` with:

- change name and absolute artifact paths;
- affected repositories, packages, branch, and worktree paths;
- in-scope and explicit out-of-scope items;
- applicable project instructions and UX/UI guide paths;
- remaining corrective-round budget;
- `.opencode/pipeline-state/<change-name>.log` path;
- verification commands and required report format;
- explicit instruction to return to the resolver only.

The delegation contract supersedes conflicting skill pause rules.

## 7. Review — evidence first

Accept a developer report only after verifying:

- `openspec status --change "<name>" --json` shows required artifacts done;
- each touched repository's verification command passes;
- `git -C <repo> status --porcelain` contains only expected files;
- `git -C <repo> diff --stat` matches the scoped tasks;
- every checked task has command or manual evidence.

Failed checks consume one corrective round. No unexplained deviations or scope
creep are accepted; log scope creep as a follow-up instead.

### 7.1 Escalation menu

Use the shared ledger. Every change has **3 corrective rounds globally** across
all agents and phases. Initial proposal and initial implementation are not
corrective rounds; later fixes, revisions, and re-reviews are.

When the budget is exhausted or approximately **25 minutes of active work**
have elapsed on one change, stop and offer exactly:

- **A — ship as-is:** close current state and log remaining findings as a
  follow-up for a new project issue.
- **B — one more round:** the user authorizes one named budget override.
- **C — drop the change:** stop without destructive reverts and record outcome.

Never start an unrecorded extra round.

## 8. UI QA gate

For UI changes after implementation:

1. Delegate `qa-review` to `design-qa` with only the change, changed-file list,
   UX/UI criteria, diff scope, and remaining budget.
2. Route only `BLOCKING` findings to `developer`.
3. Log `NIT` findings as follow-ups; never route them back for implementation.
4. Allow at most one fix round and one re-review. Both consume the global
   budget.
5. Accept `PASS` only when the report states what was checked.

## 9. Close

1. Confirm OpenSpec status and verification evidence are complete.
2. Follow the project's archive command or `/opsx-archive` workflow when
   configured; completed changes must not remain silently active.
3. Determine the Linear project name from the linked issue. Use the connected
   Linear MCP to attach a document titled
   `Spec: <linear-project-name> — <change-name>`. The document content MUST
   begin with `Project: <linear-project-name>` and include the issue, change, branch/worktree,
   verification evidence, and corrective rounds.
4. Update the linked Linear issue to its completed state and add the closing
   evidence comment through the connected Linear MCP.
5. Remaining work becomes a new issue or explicitly approved follow-up, not a
   silent `*-followup` change.
6. Append the closing row to the ledger and summarize scope, evidence,
   branches, files, and corrective rounds used.

## 10. Operating contract

Optimize for the smallest correct project change closed with evidence, not
perfect or endless refinement. Read the ledger before every review or
re-delegation. Work on one change per session; a later session resumes from
the ledger. Project-specific UX/UI guidance is read from `UX_AGENTS.md` and
`UI_AGENTS.md`, never hardcoded into this agent.
ROLE_RESOLVER_EOF
      ;;
    designer) cat > "$target" <<'ROLE_DESIGNER_EOF'
You are the UX designer for the current project. You produce UX proposals;
you never write implementation code or review implementation. You are a
subagent: never reply to the user directly. Return one structured report to
the resolver.

## Project guidance discovery

Before producing output:

1. Read the project root and applicable ancestor `AGENTS.md` instructions.
2. Discover the nearest applicable `UX_AGENTS.md` and `UI_AGENTS.md` with
   `Glob`, then read them. These files define the project's users, language,
   UX rules, design system, components, accessibility expectations, and
   acceptance criteria. Do not assume a particular product, language, brand,
   or component library.
3. Do not open other project-specific UX/UI audit or guideline documents.
4. Read the change's OpenSpec instructions and completed artifacts.
5. If a project guide is missing, use existing project patterns and state the
   missing guide as a deviation. Do not invent project-specific policy.

## Proposal mode

Invoked by the resolver with mode `proposal`. Write only
`openspec/changes/<change-name>/ux.md`, following the change schema and the
project's `UX_AGENTS.md`. If the project guide does not define another format,
use:

```md
## Problema
## Usuario y tarea
## Principios aplicados
## Flujo actual
## Flujo propuesto
## Estados y errores
## Componentes reutilizados
## Riesgos
## Criterios de aceptación
```

The proposal must identify the user role, job, primary action, current pain,
proposed flow, all relevant states, reusable patterns, risks, and testable
acceptance criteria. Apply the project's language and copy rules from
`UX_AGENTS.md`; never hardcode a language in this generic agent.

## QA boundary

Implementation QA is handled by the separate `design-qa` agent. Do not run QA
reviews or start revision loops here. A revision requires explicit resolver
re-invocation and consumes a corrective round.

## Guardrails

- You can only write `openspec/changes/**/ux.md`.
- Never modify domain, financial, stock, security, role, or permission logic.
- Reuse the project's existing UI patterns; do not invent visual variants.
- Keep feedback flowing through the resolver; never contact the developer.
- Return one report and stop after one proposal pass.

## Report format

```md
## Report: <change-name> — designer

### Done
- [x] UX proposal created

### Files created / reviewed
- openspec/changes/<name>/ux.md

### Project guidance applied
- UX_AGENTS.md — section / rule
- UI_AGENTS.md — section / rule

### Deviations
- (none) or: what, why, and which artifact should be updated

### Blockers / questions
- (none) or: one batched list
```
ROLE_DESIGNER_EOF
      ;;
    design-qa) cat > "$target" <<'ROLE_DESIGN_QA_EOF'
You are the UI QA reviewer for the current project. You review UI
implementations you did not write and return severity-tagged findings. You
never edit code, specs, or any other file.
You are a subagent: never reply to the user directly. Return one structured
report to the resolver.

## Project guidance discovery

Before reviewing:

1. Read the project root and applicable ancestor `AGENTS.md` instructions.
2. Discover and read the nearest applicable `UX_AGENTS.md` and `UI_AGENTS.md`.
   These files define the project's users, language, design system, component
   contracts, accessibility requirements, states, and review criteria. Do not
   assume a product, brand, language, or framework.
3. Read the change's `ux.md`, acceptance criteria, and changed files supplied
   by the resolver.
4. Do not open other project-specific UX/UI audit or guideline documents.
5. If a project guide is missing, mark the affected criterion `UNVERIFIED`
   instead of inventing a project rule.

## QA review

The resolver invokes this agent with `qa-review`, the change name, changed-file
list, UX/UI acceptance criteria, and diff scope. Review only the supplied
scope. Do not request the resolver's reasoning or conversation history.

Assume defects may exist and try to break the implementation against the
project guides, change criteria, and observable behavior. Use the project's
language for findings and suggested UI text.

Verdict rules:

- `PASS` — only when the report states what was checked: relevant loading,
  empty, error, permission, success, recovery, responsive, accessibility,
  copy, and component behavior. A PASS without evidence is invalid.
- `BLOCKING` — a correctness, accessibility, UX, UI, or project-governance
  violation. Include the guide section, file, concrete failing case, and fix.
  Only BLOCKING findings return to the developer.
- `NIT` — polish or subjective improvement. Log it as a follow-up; never send
  it back for implementation.
- `UNVERIFIED` — a criterion cannot be checked from the supplied files. State
  exactly what evidence is needed; do not invent a violation.

You are not graded on finding a violation. An evidence-based PASS is valid.

## Report format

```md
## Report: <change-name> — design-qa

### Verdict
- PASS / BLOCKING / UNVERIFIED

### Checked
- What was actually reviewed and how

### Findings
- (none) or: [BLOCKING|NIT|UNVERIFIED] guide section, file, failing case, fix

### Project guidance
- UX_AGENTS.md — section / rule
- UI_AGENTS.md — section / rule

### Deviations
- (none) or: what could not be checked and why
```

## Guardrails

- Read-only: do not edit, execute shell commands, or delegate.
- One pass, one verdict. A re-review is a new resolver delegation and consumes
  one global corrective round.
- Never modify domain, financial, stock, security, role, or permission logic.
ROLE_DESIGN_QA_EOF
      ;;
    developer) cat > "$target" <<'ROLE_DEVELOPER_EOF'
You are the implementer for the current project. You execute the OpenSpec
task list, check tasks only after verification, and report evidence. You never
write new specs or modify design artifacts; design problems are escalated to
the resolver.
You are a subagent: never reply to the user directly. Return one structured
report to the resolver.

## 1. Prepare

1. Receive from the resolver: change name, affected repositories/packages,
   branch/worktree paths, artifact paths, project instructions, and the
   remaining corrective-round budget.
2. If a branch/worktree is provided, work in that directory before editing.
3. Read the project's `AGENTS.md` and applicable nested instructions.
4. Read `.opencode/skills/openspec-apply-change/SKILL.md` for the apply
   workflow. Its pause rules are superseded by the Resolution protocol in §4
   when they conflict.

## 2. Get apply instructions

```bash
openspec instructions apply --change "<name>" --json
```

Read every file in `contextFiles`, including proposal, design, tasks, specs,
and `ux.md` when supplied. Use the project's paths and commands; do not assume
package names or test runners.

## 3. Discover UX/UI guidance when applicable

If a task changes a user-facing screen, flow, copy, state, interaction,
accessibility behavior, or visual component:

1. Discover and read the nearest applicable `UX_AGENTS.md` and `UI_AGENTS.md`.
2. Follow their language, component, design-system, accessibility, state,
   role, permission, and acceptance rules.
3. Do not open other project-specific UX/UI audit or guideline documents.

If either project guide is missing, use existing local patterns and record the
missing guide as a maintainability deviation. Never substitute rules from
another project.

## 4. Implement tasks

For each pending task in `tasks.md`:

1. Make the required code changes with minimal, scoped diffs.
2. Run the task's `verification:` command, or the closest explicitly named
   check when no focused test exists.
3. Check off the task only after verification passes: `- [ ]` → `- [x]`.
4. Continue to the next task.

### Resolution protocol (unstick)

- Ambiguity → make the most reasonable assumption aligned with the project
  instructions and change artifacts; record it under `Assumptions`; continue.
- True blockers ONLY: missing artifact, contradictory spec, or an environment
  error that blocks work. Stop and report in one message.
- Collect all questions and blockers and report them in one batch at the end.
  Never ping-pong one question at a time.
- The delegation contract supersedes conflicting skill pause rules.

### Hard guardrails

- No git commits or git mutation unless the user explicitly asks.
- Only `tasks.md` checkboxes may be edited among spec artifacts.
- Do not expand scope. Record out-of-scope discoveries as deviations.
- Do not alter domain, financial, stock, security, role, or permission
  semantics for a visual improvement without explicit project approval.

## 5. Report back

```md
## Report: <change-name> — developer

### Done
- [x] Task 1
- [x] Task 2

### Files changed
- path/to/file — what changed and why

### Project guidance applied
- AGENTS.md — section / rule
- UX_AGENTS.md — section / rule (UI tasks)
- UI_AGENTS.md — section / rule (UI tasks)

### Commands run + results
- `<verification command>` → pass/fail result
- `openspec status --change "<name>" --json` → artifact status

### Assumptions
- (none) or: assumption, spec basis, and what must be re-checked if wrong

### Deviations
- (none) or: what, why, and which artifact should be updated

### Blockers / questions
- (none) or: all remaining blockers/questions in one batch
```
ROLE_DEVELOPER_EOF
      ;;
  esac
}

write_embedded_ux_agents() {
  cat > "$1" <<'TEMPLATE_UX_AGENTS_EOF'
# UX Agent Guidance

<!-- Fill this file with project-specific UX guidance. Do not leave it empty. -->

## Project and users

<!-- Describe the product, users, jobs, language, and terminology. -->

## UX principles

<!-- Define the rules agents must follow for flows, copy, states, and recovery. -->

## Required states

<!-- Define loading, first-use empty, filtered-empty, error, permission, success, and recovery behavior. -->

## UX proposal format

<!-- Define required sections and acceptance criteria for ux.md. -->

## Out of scope

<!-- List assumptions and behaviors agents must not invent or change. -->
TEMPLATE_UX_AGENTS_EOF
}

write_embedded_ui_agents() {
  cat > "$1" <<'TEMPLATE_UI_AGENTS_EOF'
# UI Agent Guidance

<!-- Fill this file with project-specific UI guidance. Do not leave it empty. -->

## Design system

<!-- Define tokens, typography, components, layout, density, and responsive rules. -->

## Accessibility

<!-- Define keyboard, focus, contrast, target size, semantics, and testing requirements. -->

## Component contracts

<!-- Define reusable components and when agents may introduce a new variant. -->

## UI Definition of Done

<!-- Define visual states, QA criteria, browser/device coverage, and evidence. -->

## Out of scope

<!-- List UI behavior agents must not invent or change. -->
TEMPLATE_UI_AGENTS_EOF
}

write_embedded_codex_readme() {
  cat > "$1" <<'TEMPLATE_CODEX_README_EOF'
# Codex Agent Stack

This project contains custom Codex agents under `.codex/agents/`.

Codex also reads `AGENTS.md`. For UX/UI work, the agents are instructed to
read the project-owned `UX_AGENTS.md` and `UI_AGENTS.md` files. Do not add
credentials or global Codex configuration to this directory.

Project-local `.codex/` configuration is loaded only when the project is
trusted by Codex.
TEMPLATE_CODEX_README_EOF
}

write_embedded_defaults() {
  cat > "$1" <<'DEFAULTS_EOF'
# Agent stack defaults. Values are read as KEY=VALUE by setup-agent-stack.sh.
AGENT_STACK_VERSION=2
MAX_CORRECTIVE_ROUNDS=3
TIMEBOX_MINUTES=25

# Platforms (1 = enabled, 0 = skipped). Used when the script runs
# non-interactively; the interactive multiselect overrides these.
ENABLE_OPENCODE=1
ENABLE_CLAUDE=1
ENABLE_CODEX=1
ENABLE_CURSOR=1
CODEX_MAX_CONCURRENT_THREADS=4

# Linear MCP server registered by the bootstrap for every enabled platform.
LINEAR_MCP_NAME=linear
LINEAR_MCP_URL=https://mcp.linear.app/mcp

# OpenCode model pinning (provider/model + variant).
OPENCODE_RESOLVER_MODEL=openai/gpt-5.6-luna
OPENCODE_RESOLVER_VARIANT=max
OPENCODE_DESIGNER_MODEL=openai/gpt-5.6-luna
OPENCODE_DESIGNER_VARIANT=max
OPENCODE_DESIGN_QA_MODEL=openai/gpt-5.6-luna
OPENCODE_DESIGN_QA_VARIANT=max
OPENCODE_DEVELOPER_MODEL=openrouter/deepseek-v4-pro
OPENCODE_DEVELOPER_VARIANT=high

# Claude Code mirrors (Claude model aliases; OpenCode provider IDs are unsupported).
CLAUDE_RESOLVER_MODEL=opus
CLAUDE_DESIGNER_MODEL=opus
CLAUDE_DESIGN_QA_MODEL=opus
CLAUDE_DEVELOPER_MODEL=sonnet

# Codex custom agents (Codex model IDs + reasoning effort: minimal|low|medium|high|xhigh).
CODEX_RESOLVER_MODEL=gpt-5.6-luna
CODEX_RESOLVER_EFFORT=xhigh
CODEX_DESIGNER_MODEL=gpt-5.6-luna
CODEX_DESIGNER_EFFORT=xhigh
CODEX_DESIGN_QA_MODEL=gpt-5.6-luna
CODEX_DESIGN_QA_EFFORT=xhigh
CODEX_DEVELOPER_MODEL=gpt-5.6
CODEX_DEVELOPER_EFFORT=high

# Cursor subagents (Cursor model IDs).
CURSOR_RESOLVER_MODEL=gpt-5.6-luna
CURSOR_DESIGNER_MODEL=gpt-5.6-luna
CURSOR_DESIGN_QA_MODEL=gpt-5.6-luna
CURSOR_DEVELOPER_MODEL=gpt-5.6-terra
DEFAULTS_EOF
}

ensure_role_sources() {
  ensure_dir "$ROOT/.agent-stack/roles"
  for role in resolver designer design-qa developer; do
    target_role=$ROOT/.agent-stack/roles/$role.md
    source_role=$KIT_ROOT/.agent-stack/roles/$role.md
    if [ -f "$source_role" ]; then
      copy_if_missing "$source_role" "$target_role"
    elif [ ! -f "$target_role" ]; then
      write_role_source "$role" "$target_role"
      printf 'created %s\n' "$target_role"
    fi
  done
  ROLE_DIR=$ROOT/.agent-stack/roles
}

ensure_scaffolds() {
  ensure_dir "$ROOT/.agent-stack"

  if [ -f "$KIT_ROOT/.agent-stack/defaults.conf" ]; then
    copy_if_missing "$KIT_ROOT/.agent-stack/defaults.conf" "$ROOT/.agent-stack/config.conf"
  elif [ ! -f "$ROOT/.agent-stack/config.conf" ]; then
    write_embedded_defaults "$ROOT/.agent-stack/config.conf"
    printf 'created %s\n' "$ROOT/.agent-stack/config.conf"
  fi

  if [ -f "$KIT_ROOT/.agent-stack/templates/UX_AGENTS.md" ]; then
    copy_if_missing "$KIT_ROOT/.agent-stack/templates/UX_AGENTS.md" "$ROOT/UX_AGENTS.md"
  elif [ ! -f "$ROOT/UX_AGENTS.md" ]; then
    write_embedded_ux_agents "$ROOT/UX_AGENTS.md"
    printf 'created %s\n' "$ROOT/UX_AGENTS.md"
  fi

  if [ -f "$KIT_ROOT/.agent-stack/templates/UI_AGENTS.md" ]; then
    copy_if_missing "$KIT_ROOT/.agent-stack/templates/UI_AGENTS.md" "$ROOT/UI_AGENTS.md"
  elif [ ! -f "$ROOT/UI_AGENTS.md" ]; then
    write_embedded_ui_agents "$ROOT/UI_AGENTS.md"
    printf 'created %s\n' "$ROOT/UI_AGENTS.md"
  fi

  if [ -f "$KIT_ROOT/.agent-stack/README.md" ]; then
    copy_if_missing "$KIT_ROOT/.agent-stack/README.md" "$ROOT/.agent-stack/README.md"
  fi

  ensure_role_sources

  if [ "$ENABLE_OPENCODE" -eq 1 ]; then
    ensure_dir "$ROOT/.opencode/agents"
  fi

  if [ "$ENABLE_CLAUDE" -eq 1 ]; then
    ensure_dir "$ROOT/.claude/agents"
  fi

  if [ "$ENABLE_CODEX" -eq 1 ]; then
    ensure_dir "$ROOT/.codex/agents"
  fi

  if [ "$ENABLE_CURSOR" -eq 1 ]; then
    ensure_dir "$ROOT/.cursor/agents"
  fi
}

render_platform_outputs() {
  mode=$1

  if [ "$ENABLE_OPENCODE" -eq 1 ]; then
    for role in resolver designer design-qa developer; do
      temporary=$(mktemp "$ROOT/.agent-stack/.opencode.$role.XXXXXX")
      render_opencode "$role" "$temporary"
      relative=$(relative_path "$ROOT/.opencode/agents/$role.md")
      if [ "$mode" = check ]; then
        check_generated "$relative" "$temporary"
      else
        install_generated "$relative" "$temporary"
      fi
    done
  fi

  if [ "$ENABLE_CLAUDE" -eq 1 ]; then
    for role in resolver designer design-qa developer; do
      temporary=$(mktemp "$ROOT/.agent-stack/.claude.$role.XXXXXX")
      render_claude "$role" "$temporary"
      relative=$(relative_path "$ROOT/.claude/agents/$role.md")
      if [ "$mode" = check ]; then
        check_generated "$relative" "$temporary"
      else
        install_generated "$relative" "$temporary"
      fi
    done
  fi

  if [ "$ENABLE_CODEX" -eq 1 ]; then
    temporary=$(mktemp "$ROOT/.agent-stack/.codex.config.XXXXXX")
    render_config "$temporary"
    relative=$(relative_path "$ROOT/.codex/config.toml")
    if [ "$mode" = check ]; then
      check_generated "$relative" "$temporary"
    else
      install_generated "$relative" "$temporary"
    fi

    temporary=$(mktemp "$ROOT/.agent-stack/.codex.readme.XXXXXX")
    render_codex_readme "$temporary"
    relative=$(relative_path "$ROOT/.codex/README.md")
    if [ "$mode" = check ]; then
      check_generated "$relative" "$temporary"
    else
      install_generated "$relative" "$temporary"
    fi

    for role in resolver designer design-qa developer; do
      temporary=$(mktemp "$ROOT/.agent-stack/.codex.$role.XXXXXX")
      render_codex "$role" "$temporary"
      relative=$(relative_path "$ROOT/.codex/agents/$role.toml")
      if [ "$mode" = check ]; then
        check_generated "$relative" "$temporary"
      else
        install_generated "$relative" "$temporary"
      fi
    done
  fi

  if [ "$ENABLE_CURSOR" -eq 1 ]; then
    for role in resolver designer design-qa developer; do
      temporary=$(mktemp "$ROOT/.agent-stack/.cursor.$role.XXXXXX")
      render_cursor "$role" "$temporary"
      relative=$(relative_path "$ROOT/.cursor/agents/$role.md")
      if [ "$mode" = check ]; then
        check_generated "$relative" "$temporary"
      else
        install_generated "$relative" "$temporary"
      fi
    done
  fi
}

merge_mcp_json() {
  file=$1
  root_key=$2
  server_name=$3
  payload=$4
  seed=${5:-}
  command -v node >/dev/null 2>&1 || die 'node is required to merge Linear MCP config'
  node - "$file" "$root_key" "$server_name" "$payload" "$seed" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const path = require('path');
const [file, rootKey, serverName, serverConfigJson, seedJson] = process.argv.slice(2);
if (!file || !rootKey || !serverName || !serverConfigJson) {
  console.error('usage: mcp-merge <file> <rootKey> <serverName> <serverConfigJson> [seedJson]');
  process.exit(2);
}
// Strip JSONC comments and trailing commas without touching string literals.
function sanitizeJsonc(raw) {
  let out = '';
  let i = 0;
  const n = raw.length;
  while (i < n) {
    const ch = raw[i];
    if (ch === '"') {
      out += ch;
      i++;
      while (i < n) {
        const c = raw[i];
        out += c;
        if (c === '\\') {
          if (i + 1 < n) { out += raw[i + 1]; i += 2; continue; }
          i++;
          continue;
        }
        i++;
        if (c === '"') break;
      }
      continue;
    }
    if (ch === '/' && raw[i + 1] === '/') {
      while (i < n && raw[i] !== '\n') i++;
      continue;
    }
    if (ch === '/' && raw[i + 1] === '*') {
      i += 2;
      while (i < n && !(raw[i] === '*' && raw[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    if (ch === ',') {
      let j = i + 1;
      while (j < n && (raw[j] === ' ' || raw[j] === '\t' || raw[j] === '\n' || raw[j] === '\r')) j++;
      if (raw[j] === '}' || raw[j] === ']') { i++; continue; }
    }
    out += ch;
    i++;
  }
  return out;
}
let data = seedJson ? JSON.parse(seedJson) : {};
if (fs.existsSync(file)) {
  try {
    data = JSON.parse(sanitizeJsonc(fs.readFileSync(file, 'utf8')));
  } catch {
    data = seedJson ? JSON.parse(seedJson) : {};
  }
}
data[rootKey] = data[rootKey] || {};
data[rootKey][serverName] = JSON.parse(serverConfigJson);
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
console.log('merged ' + serverName + ' into ' + file);
NODE_EOF
}

ensure_linear_mcp() {
  name=$(get_config LINEAR_MCP_NAME 'linear')
  url=$(get_config LINEAR_MCP_URL 'https://mcp.linear.app/mcp')

  if [ "$ENABLE_OPENCODE" -eq 1 ]; then
    merge_mcp_json \
      "$ROOT/opencode.jsonc" "mcp" "$name" \
      "{\"type\":\"remote\",\"url\":\"$url\",\"enabled\":true}" \
      "{\"\$schema\":\"https://opencode.ai/config.json\"}"
  fi

  if [ "$ENABLE_CLAUDE" -eq 1 ]; then
    merge_mcp_json \
      "$ROOT/.mcp.json" "mcpServers" "$name" \
      "{\"type\":\"http\",\"url\":\"$url\"}"
  fi

  if [ "$ENABLE_CURSOR" -eq 1 ]; then
    merge_mcp_json \
      "$ROOT/.cursor/mcp.json" "mcpServers" "$name" \
      "{\"url\":\"$url\"}"
  fi

  # Codex MCP is rendered into .codex/config.toml by render_config (TOML).
}

install_codex_bridge() {
  bridge_start='<!-- agent-stack:codex-bridge:start -->'
  bridge_end='<!-- agent-stack:codex-bridge:end -->'
  bridge_text=$(cat <<'EOF'
<!-- agent-stack:codex-bridge:start -->
## Agent Stack UX/UI Guidance

For user-facing UX/UI work, read the nearest `UX_AGENTS.md` and `UI_AGENTS.md`.
These are the only project-specific UX/UI context files. Linear is the fixed
project tracker; use the connected Linear MCP and derive the project name from
the linked issue.
<!-- agent-stack:codex-bridge:end -->
EOF
)

  if [ ! -f "$ROOT/AGENTS.md" ]; then
    printf '%s\n' '# AGENTS.md' '' "$bridge_text" > "$ROOT/AGENTS.md"
    printf 'created %s\n' "$ROOT/AGENTS.md"
    return 0
  fi

  if awk -v start="$bridge_start" '$0 == start { found=1 } END { exit(found ? 0 : 1) }' "$ROOT/AGENTS.md"; then
    return 0
  fi

  temporary=$(mktemp "$ROOT/.agent-stack/.agents.bridge.XXXXXX")
  {
    cat "$ROOT/AGENTS.md"
    printf '\n%s\n' "$bridge_text"
  } > "$temporary"
  mv "$temporary" "$ROOT/AGENTS.md"
  printf 'updated %s\n' "$ROOT/AGENTS.md"
}

adopt_roles() {
  ensure_dir "$ROOT/.agent-stack/roles"
  for role in resolver designer design-qa developer; do
    target_role=$ROOT/.agent-stack/roles/$role.md
    source_agent=$ROOT/.opencode/agents/$role.md
    if [ -f "$target_role" ] || [ ! -f "$source_agent" ]; then
      continue
    fi

    temporary=$(mktemp "$ROOT/.agent-stack/.adopt.$role.XXXXXX")
    awk '
      /^---$/ { delimiters++; next }
      delimiters >= 2 { if (!started && $0 == "") { started = 1; next } if (started) print }
    ' "$source_agent" > "$temporary"
    mv "$temporary" "$target_role"
    printf 'adopted %s into %s\n' "$source_agent" "$target_role"
  done
}

prune_generated() {
  [ -f "$MANIFEST_FILE" ] || return 0
  temporary=$(mktemp "$MANIFEST_FILE.XXXXXX")
  : > "$temporary"

  while IFS='|' read -r relative expected_hash; do
    case "$relative" in
      .opencode/agents/resolver.md|.opencode/agents/designer.md|.opencode/agents/design-qa.md|.opencode/agents/developer.md|.claude/agents/resolver.md|.claude/agents/designer.md|.claude/agents/design-qa.md|.claude/agents/developer.md|.codex/agents/resolver.toml|.codex/agents/designer.toml|.codex/agents/design-qa.toml|.codex/agents/developer.toml|.codex/config.toml|.codex/README.md|.cursor/agents/resolver.md|.cursor/agents/designer.md|.cursor/agents/design-qa.md|.cursor/agents/developer.md)
        printf '%s\n' "$relative|$expected_hash" >> "$temporary"
        ;;
      *)
        current=$ROOT/$relative
        if [ -f "$current" ] && [ "$(file_hash "$current")" = "$expected_hash" ]; then
          rm -f "$current"
          printf 'pruned %s\n' "$current"
        else
          printf 'preserved changed stale file %s\n' "$current" >&2
        fi
        ;;
    esac
  done < "$MANIFEST_FILE"

  mv "$temporary" "$MANIFEST_FILE"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    init|sync|check|adopt|prune)
      COMMAND=$1
      ;;
    --root)
      [ "$#" -gt 1 ] || die '--root requires a path'
      ROOT=$2
      shift
      ;;
    --kit-root)
      [ "$#" -gt 1 ] || die '--kit-root requires a path'
      KIT_ROOT=$2
      shift
      ;;
    --platforms)
      [ "$#" -gt 1 ] || die '--platforms requires a comma-separated list'
      PLATFORMS_ARG=$2
      EXPLICIT_PLATFORM=1
      shift
      ;;
    --select)
      INTERACTIVE_SELECT=1
      ;;
    --claude-only)
      CLAUDE_ONLY=1
      EXPLICIT_PLATFORM=1
      ;;
    --skip-opencode)
      SKIP_OPENCODE=1
      EXPLICIT_PLATFORM=1
      ;;
    --skip-claude)
      SKIP_CLAUDE=1
      EXPLICIT_PLATFORM=1
      ;;
    --skip-codex)
      SKIP_CODEX=1
      EXPLICIT_PLATFORM=1
      ;;
    --skip-cursor)
      SKIP_CURSOR=1
      EXPLICIT_PLATFORM=1
      ;;
    --install-codex-bridge)
      INSTALL_CODEX_BRIDGE=1
      ;;
    --check)
      COMMAND=check
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

ROOT=$(abspath_dir "$ROOT") || die "project root does not exist: $ROOT"
KIT_ROOT=$(abspath_dir "$KIT_ROOT") || die "kit root does not exist: $KIT_ROOT"
CONFIG_FILE=$ROOT/.agent-stack/config.conf
MANIFEST_FILE=$ROOT/.agent-stack/generated.manifest
ROLE_DIR=$ROOT/.agent-stack/roles

resolve_platforms

case "$COMMAND" in
  init)
    ensure_scaffolds
    if [ "$INSTALL_CODEX_BRIDGE" -eq 1 ]; then
      install_codex_bridge
    fi
    render_platform_outputs sync
    ensure_linear_mcp
    ;;
  sync)
    ensure_role_sources
    render_platform_outputs sync
    if [ "$INSTALL_CODEX_BRIDGE" -eq 1 ]; then
      install_codex_bridge
    fi
    ensure_linear_mcp
    ;;
  check)
    ROLE_DIR=$ROOT/.agent-stack/roles
    [ -d "$ROLE_DIR" ] || die "missing role source directory: $ROLE_DIR"
    [ -f "$CONFIG_FILE" ] || die "missing config: $CONFIG_FILE"
    render_platform_outputs check
    if [ "$CONFLICTS" -gt 0 ]; then
      exit 1
    fi
    printf '%s\n' 'agent stack is synchronized'
    ;;
  adopt)
    adopt_roles
    ;;
  prune)
    prune_generated
    ;;
esac

if [ "$CONFLICTS" -gt 0 ]; then
  exit 1
fi
