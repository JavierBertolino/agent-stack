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
MCP_ARG=
EXPLICIT_MCP=0
SPECS_REPOSITORY_ARG=
SPECS_REPOSITORY_BASE_BRANCH_ARG=
INTERACTIVE_WIZARD=0
PERSIST_SELECTION=0
CONFLICTS=0

# Per-platform enable flags (0 = skip, 1 = render). Resolved later from config
# defaults, CLI flags, or the interactive multiselect menu.
ENABLE_OPENCODE=1
ENABLE_CLAUDE=1
ENABLE_CODEX=1
ENABLE_CURSOR=1

# MCP and model settings are loaded from project config, then optionally
# changed by the interactive installer wizard.
MCP_LINEAR_ENABLED=1
MCP_LINEAR_NAME=linear
MCP_LINEAR_URL=https://mcp.linear.app/mcp
MCP_TRELLO_ENABLED=0
MCP_TRELLO_NAME=trello
MCP_TRELLO_URL=https://mcp.trello.com/mcp
SPECS_REPOSITORY=
SPECS_REPOSITORY_BASE_BRANCH=main

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
  --mcp LIST                  MCP integrations: none, linear, trello, both.
  --specs-repository REPO     GitHub owner/repo for finalized OpenSpec uploads.
  --specs-base-branch BRANCH  Base branch for the specs repository PR.
  --claude-only               Only render/check Claude mirrors.
  --skip-opencode             Do not render/check OpenCode agents.
  --skip-claude               Do not render/check Claude agents.
  --skip-codex                Do not render/check Codex files.
  --skip-cursor               Do not render/check Cursor agents.
  --install-codex-bridge      Add the managed guidance block to AGENTS.md.
  -h, --help                  Show this help.

Platforms: running interactively (init/sync) with no platform flag shows a
detected-harness multiselect menu for OpenCode, Claude Code, Codex, and Cursor,
then asks for the specs repository, each selected role's model, and supported
thinking level.
Non-interactive runs use the ENABLE_* and model defaults from
.agent-stack/config.conf. `SPECS_REPOSITORY` must be set through the wizard,
`--specs-repository`, or that config file.

MCP integrations: the wizard can register Linear and/or Trello in every
enabled platform's config: opencode.jsonc (OpenCode), .mcp.json (Claude),
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

has_config_key() {
  key=$1
  [ -f "$CONFIG_FILE" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { found=1; exit } END { exit(found ? 0 : 1) }' "$CONFIG_FILE"
}

set_config() {
  key=$1
  value=$2
  ensure_dir "$(dirname -- "$CONFIG_FILE")"
  temporary=$(mktemp "$CONFIG_FILE.XXXXXX")

  if [ -f "$CONFIG_FILE" ]; then
    awk -F= -v wanted="$key" -v replacement="$key=$value" '
      BEGIN { found = 0 }
      $1 == wanted {
        if (!found) print replacement
        found = 1
        next
      }
      { print }
      END {
        if (!found) print replacement
      }
    ' "$CONFIG_FILE" > "$temporary"
  else
    printf '%s\n' "$key=$value" > "$temporary"
  fi

  mv "$temporary" "$CONFIG_FILE"
}

file_contains() {
  file=$1
  needle=$2
  [ -f "$file" ] || return 1
  awk -v wanted="$needle" 'index($0, wanted) { found=1; exit } END { exit(found ? 0 : 1) }' "$file"
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

platform_is_configured() {
  case "$1" in
    opencode)
      [ -d "$ROOT/.opencode/agents" ] || [ -f "$ROOT/opencode.jsonc" ]
      ;;
    claude)
      [ -d "$ROOT/.claude/agents" ] || [ -f "$ROOT/.mcp.json" ] || [ -f "$ROOT/CLAUDE.md" ]
      ;;
    codex)
      [ -d "$ROOT/.codex/agents" ] || [ -f "$ROOT/.codex/config.toml" ]
      ;;
    cursor)
      [ -d "$ROOT/.cursor/agents" ] || [ -f "$ROOT/.cursor/mcp.json" ]
      ;;
    *) return 1 ;;
  esac
}

any_platform_configured() {
  platform_is_configured opencode ||
  platform_is_configured claude ||
  platform_is_configured codex ||
  platform_is_configured cursor
}

platform_default_enabled() {
  platform=$1
  configured=0
  platform_is_configured "$platform" && configured=1

  case "$platform" in
    opencode) key=ENABLE_OPENCODE ;;
    claude) key=ENABLE_CLAUDE ;;
    codex) key=ENABLE_CODEX ;;
    cursor) key=ENABLE_CURSOR ;;
    *) return 1 ;;
  esac

  if [ "$(get_config "$key" 1)" = 0 ]; then
    printf '%s\n' 0
  elif [ "$configured" = 1 ] || ! any_platform_configured; then
    printf '%s\n' 1
  else
    printf '%s\n' 0
  fi
}

platform_marker() {
  if platform_is_configured "$1"; then
    printf '%s\n' ' (detected)'
  else
    printf '%s\n' ''
  fi
}

select_platforms_interactive() {
  [ -t 0 ] || die "--select requires an interactive terminal"

  o=$(platform_default_enabled opencode)
  c=$(platform_default_enabled claude)
  x=$(platform_default_enabled codex)
  r=$(platform_default_enabled cursor)

  while :; do
    printf '\nSelect platforms to configure (enter number to toggle, Enter to confirm):\n'
    if [ "$o" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  1 %s OpenCode%s\n' "$m" "$(platform_marker opencode)"
    if [ "$c" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  2 %s Claude Code%s\n' "$m" "$(platform_marker claude)"
    if [ "$x" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  3 %s Codex%s\n' "$m" "$(platform_marker codex)"
    if [ "$r" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  4 %s Cursor%s\n' "$m" "$(platform_marker cursor)"
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
  INTERACTIVE_WIZARD=1
  PERSIST_SELECTION=1
}

apply_mcp_selection() {
  case "$1" in
    none)
      MCP_LINEAR_ENABLED=0
      MCP_TRELLO_ENABLED=0
      ;;
    linear)
      MCP_LINEAR_ENABLED=1
      MCP_TRELLO_ENABLED=0
      ;;
    trello)
      MCP_LINEAR_ENABLED=0
      MCP_TRELLO_ENABLED=1
      ;;
    both)
      MCP_LINEAR_ENABLED=1
      MCP_TRELLO_ENABLED=1
      ;;
    *) die "unknown MCP selection: $1 (use none, linear, trello, or both)" ;;
  esac
}

select_mcp_interactive() {
  linear=$MCP_LINEAR_ENABLED
  trello=$MCP_TRELLO_ENABLED

  while :; do
    printf '\nSelect MCP integrations to configure (enter number to toggle, Enter to confirm):\n'
    if [ "$linear" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  1 %s Linear\n' "$m"
    if [ "$trello" = 1 ]; then m='[x]'; else m='[ ]'; fi
    printf '  2 %s Trello\n' "$m"
    printf '  a) select both   n) select none\n'
    printf '> '
    IFS= read -r choice || die 'interactive MCP selection aborted'
    case "$choice" in
      1) [ "$linear" = 1 ] && linear=0 || linear=1 ;;
      2) [ "$trello" = 1 ] && trello=0 || trello=1 ;;
      a|all) linear=1; trello=1 ;;
      n|none) linear=0; trello=0 ;;
      ''|d|done) break ;;
      *) printf 'choose 1-2, a, n, or Enter\n' ;;
    esac
  done

  MCP_LINEAR_ENABLED=$linear
  MCP_TRELLO_ENABLED=$trello
  PERSIST_SELECTION=1
}

resolve_mcp() {
  MCP_LINEAR_ENABLED=$(get_config MCP_LINEAR_ENABLED 1)
  MCP_LINEAR_NAME=$(get_config MCP_LINEAR_NAME "$(get_config LINEAR_MCP_NAME linear)")
  MCP_LINEAR_URL=$(get_config MCP_LINEAR_URL "$(get_config LINEAR_MCP_URL https://mcp.linear.app/mcp)")
  MCP_TRELLO_ENABLED=$(get_config MCP_TRELLO_ENABLED 0)
  MCP_TRELLO_NAME=$(get_config MCP_TRELLO_NAME trello)
  MCP_TRELLO_URL=$(get_config MCP_TRELLO_URL https://mcp.trello.com/mcp)

  if [ -n "$MCP_ARG" ]; then
    apply_mcp_selection "$MCP_ARG"
    PERSIST_SELECTION=1
  elif [ "$INTERACTIVE_WIZARD" = 1 ]; then
    select_mcp_interactive
  fi
}

resolve_delivery_config() {
  SPECS_REPOSITORY=$(get_config SPECS_REPOSITORY '')
  SPECS_REPOSITORY_BASE_BRANCH=$(get_config SPECS_REPOSITORY_BASE_BRANCH main)

  if [ -n "$SPECS_REPOSITORY_ARG" ]; then
    SPECS_REPOSITORY=$SPECS_REPOSITORY_ARG
    PERSIST_SELECTION=1
  fi
  if [ -n "$SPECS_REPOSITORY_BASE_BRANCH_ARG" ]; then
    SPECS_REPOSITORY_BASE_BRANCH=$SPECS_REPOSITORY_BASE_BRANCH_ARG
    PERSIST_SELECTION=1
  fi
}

configure_delivery_interactive() {
  while :; do
    current=$SPECS_REPOSITORY
    printf '\nOpenSpec specs repository (GitHub owner/repo; required for setup, Enter keeps current):\n'
    printf '  current: %s\n> ' "${current:-not configured}"
    IFS= read -r repository || die 'interactive configuration aborted'
    case "$repository" in
      '') ;;
      *) SPECS_REPOSITORY=$repository ;;
    esac
    if specs_repository_is_valid "$SPECS_REPOSITORY"; then
      break
    fi
    printf 'a GitHub repository in OWNER/REPO form is required\n' >&2
  done

  if [ -n "$SPECS_REPOSITORY" ]; then
    current=$SPECS_REPOSITORY_BASE_BRANCH
    printf 'Specs repository base branch (Enter keeps current):\n'
    printf '  current: %s\n> ' "$current"
    IFS= read -r branch || die 'interactive configuration aborted'
    [ -n "$branch" ] && SPECS_REPOSITORY_BASE_BRANCH=$branch
  fi
  PERSIST_SELECTION=1
}

specs_repository_is_valid() {
  case "$1" in
    */*) return 0 ;;
    *) return 1 ;;
  esac
}

require_specs_repository() {
  specs_repository_is_valid "$SPECS_REPOSITORY" || die 'SPECS_REPOSITORY is required; use --specs-repository OWNER/REPO or edit .agent-stack/config.conf'
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

model_key_for() {
  case "$1:$2" in
    opencode:resolver) printf '%s\n' OPENCODE_RESOLVER_MODEL ;;
    opencode:designer) printf '%s\n' OPENCODE_DESIGNER_MODEL ;;
    opencode:design-qa) printf '%s\n' OPENCODE_DESIGN_QA_MODEL ;;
    opencode:developer) printf '%s\n' OPENCODE_DEVELOPER_MODEL ;;
    claude:resolver) printf '%s\n' CLAUDE_RESOLVER_MODEL ;;
    claude:designer) printf '%s\n' CLAUDE_DESIGNER_MODEL ;;
    claude:design-qa) printf '%s\n' CLAUDE_DESIGN_QA_MODEL ;;
    claude:developer) printf '%s\n' CLAUDE_DEVELOPER_MODEL ;;
    codex:resolver) printf '%s\n' CODEX_RESOLVER_MODEL ;;
    codex:designer) printf '%s\n' CODEX_DESIGNER_MODEL ;;
    codex:design-qa) printf '%s\n' CODEX_DESIGN_QA_MODEL ;;
    codex:developer) printf '%s\n' CODEX_DEVELOPER_MODEL ;;
    cursor:resolver) printf '%s\n' CURSOR_RESOLVER_MODEL ;;
    cursor:designer) printf '%s\n' CURSOR_DESIGNER_MODEL ;;
    cursor:design-qa) printf '%s\n' CURSOR_DESIGN_QA_MODEL ;;
    cursor:developer) printf '%s\n' CURSOR_DEVELOPER_MODEL ;;
    *) return 1 ;;
  esac
}

thinking_key_for() {
  case "$1:$2" in
    opencode:resolver) printf '%s\n' OPENCODE_RESOLVER_VARIANT ;;
    opencode:designer) printf '%s\n' OPENCODE_DESIGNER_VARIANT ;;
    opencode:design-qa) printf '%s\n' OPENCODE_DESIGN_QA_VARIANT ;;
    opencode:developer) printf '%s\n' OPENCODE_DEVELOPER_VARIANT ;;
    claude:resolver) printf '%s\n' CLAUDE_RESOLVER_EFFORT ;;
    claude:designer) printf '%s\n' CLAUDE_DESIGNER_EFFORT ;;
    claude:design-qa) printf '%s\n' CLAUDE_DESIGN_QA_EFFORT ;;
    claude:developer) printf '%s\n' CLAUDE_DEVELOPER_EFFORT ;;
    codex:resolver) printf '%s\n' CODEX_RESOLVER_EFFORT ;;
    codex:designer) printf '%s\n' CODEX_DESIGNER_EFFORT ;;
    codex:design-qa) printf '%s\n' CODEX_DESIGN_QA_EFFORT ;;
    codex:developer) printf '%s\n' CODEX_DEVELOPER_EFFORT ;;
    cursor:*) printf '%s\n' '' ;;
    *) return 1 ;;
  esac
}

model_default_for() {
  # Models are discovered from the active harness/catalog. An empty value
  # means the generated agent inherits the harness default.
  printf '%s\n' ''
}

thinking_default_for() {
  case "$1:$2" in
    opencode:resolver|opencode:designer|opencode:design-qa) printf '%s\n' max ;;
    opencode:developer) printf '%s\n' high ;;
    claude:resolver|claude:designer|claude:design-qa|claude:developer) printf '%s\n' high ;;
    codex:resolver|codex:designer|codex:design-qa) printf '%s\n' xhigh ;;
    codex:developer) printf '%s\n' high ;;
    cursor:*) printf '%s\n' '' ;;
    *) return 1 ;;
  esac
}

prompt_option() {
  label=$1
  current=$2
  shift 2

  while :; do
    printf '\n%s\n' "$label"
    printf '  current: %s\n' "$current"
    index=1
    for option in "$@"; do
      printf '  %s) %s\n' "$index" "$option"
      index=$((index + 1))
    done
    printf '  c) custom value\n'
    printf '  Enter keeps the current value\n> '
    IFS= read -r choice || die 'interactive configuration aborted'

    if [ -z "$choice" ]; then
      PROMPT_VALUE=$current
      return 0
    fi

    case "$choice" in
      c|custom)
        printf 'Custom value: '
        IFS= read -r custom || die 'interactive configuration aborted'
        [ -n "$custom" ] || { printf 'value cannot be empty\n' >&2; continue; }
        PROMPT_VALUE=$custom
        return 0
        ;;
      *[!0-9]*)
        printf 'choose a listed number, c, or Enter\n' >&2
        continue
        ;;
    esac

    index=1
    selected=
    for option in "$@"; do
      if [ "$choice" = "$index" ]; then
        selected=$option
        break
      fi
      index=$((index + 1))
    done
    if [ -n "$selected" ]; then
      PROMPT_VALUE=$selected
      return 0
    fi
    printf 'choose a listed number, c, or Enter\n' >&2
  done
}

discover_configured_models() {
  platform=$1
  case "$platform" in
    opencode|claude|cursor)
      for file in "$ROOT/.${platform}/agents/"*.md; do
        [ -f "$file" ] || continue
        awk -F': ' '/^model: / && $2 != "" { print $2 }' "$file"
      done
      ;;
    codex)
      for file in "$ROOT/.codex/agents/"*.toml; do
        [ -f "$file" ] || continue
        awk -F'"' '/^model = / && $2 != "" { print $2 }' "$file"
      done
      ;;
  esac
}

discover_models_for() {
  platform=$1
  case "$platform" in
    opencode)
      if command -v opencode >/dev/null 2>&1; then
        opencode models 2>/dev/null | awk 'index($0, "/") > 0 { print }' || true
      elif command -v pi >/dev/null 2>&1; then
        # Pi exposes the same provider/model-shaped catalog when OpenCode is
        # not installed. It is a discovery source, not a required runtime.
        pi --list-models 2>/dev/null | awk 'NR > 1 && $1 != "provider" && NF >= 2 { print $1 "/" $2 }' || true
      fi
      ;;
    claude|codex|cursor)
      # These CLIs do not expose a stable local model-list command. Existing
      # generated models are still offered, and the prompt accepts any ID.
      ;;
  esac
  discover_configured_models "$platform"
}

prompt_custom_model() {
  label=$1
  current=$2
  printf '%s\n' "$label"
  printf '  current: %s\n' "${current:-harness default}"
  printf 'Model ID or alias (Enter keeps current): '
  IFS= read -r custom || die 'interactive configuration aborted'
  if [ -n "$custom" ]; then
    PROMPT_VALUE=$custom
  else
    PROMPT_VALUE=$current
  fi
}

prompt_discovered_model() {
  label=$1
  current=$2
  catalog=$3

  if [ ! -s "$catalog" ]; then
    printf 'No local model catalog is available for %s.\n' "$label"
    prompt_custom_model "$label" "$current"
    return 0
  fi

  active=$catalog
  while :; do
    count=$(awk 'END { print NR + 0 }' "$active")
    printf '\n%s\n' "$label"
    printf '  current: %s\n' "${current:-harness default}"
    if [ "$count" -gt 40 ]; then
      printf '  Showing the first 40 of %s available models.\n' "$count"
    fi
    index=1
    while IFS= read -r option; do
      printf '  %s) %s\n' "$index" "$option"
      index=$((index + 1))
      [ "$index" -gt 40 ] && break
    done < "$active"
    printf '  s) search the available model catalog\n'
    printf '  c) enter a custom model ID or alias\n'
    printf '  Enter keeps the current value\n> '
    IFS= read -r choice || die 'interactive configuration aborted'

    if [ -z "$choice" ]; then
      PROMPT_VALUE=$current
      [ "$active" = "$catalog" ] || rm -f "$active"
      return 0
    fi

    case "$choice" in
      c|custom)
        prompt_custom_model "$label" "$current"
        [ "$active" = "$catalog" ] || rm -f "$active"
        return 0
        ;;
      s|search)
        printf 'Search term: '
        IFS= read -r query || die 'interactive configuration aborted'
        [ -n "$query" ] || continue
        searched=$(mktemp "$ROOT/.agent-stack/.models.filtered.XXXXXX")
        awk -v query="$query" 'index(tolower($0), tolower(query)) { print }' "$catalog" > "$searched"
        if [ ! -s "$searched" ]; then
          rm -f "$searched"
          printf 'No available models matched "%s".\n' "$query" >&2
          continue
        fi
        if [ "$active" != "$catalog" ]; then
          rm -f "$active"
        fi
        active=$searched
        ;;
      *[!0-9]*)
        printf 'choose a listed number, s, c, or Enter\n' >&2
        ;;
      *)
        selected=$(awk -v wanted="$choice" 'NR == wanted { print; exit }' "$active")
        if [ -n "$selected" ]; then
          PROMPT_VALUE=$selected
          [ "$active" = "$catalog" ] || rm -f "$active"
          return 0
        fi
        printf 'choose a listed number, s, c, or Enter\n' >&2
        ;;
    esac
  done
}

prompt_model_value() {
  platform=$1
  role=$2
  current=$3
  catalog=$(mktemp "$ROOT/.agent-stack/.models.XXXXXX")
  {
    discover_models_for "$platform"
  } | awk 'NF && !seen[$0]++' > "$catalog"
  if [ -n "$current" ] && ! awk -v wanted="$current" '$0 == wanted { found=1; exit } END { exit(found ? 0 : 1) }' "$catalog"; then
    temporary=$(mktemp "$ROOT/.agent-stack/.models.current.XXXXXX")
    printf '%s\n' "$current" > "$temporary"
    awk '{ print }' "$catalog" >> "$temporary"
    mv "$temporary" "$catalog"
  fi
  prompt_discovered_model "$platform $role model" "$current" "$catalog"
  PROMPT_MODEL_VALUE=$PROMPT_VALUE
  rm -f "$catalog"

  thinking_key=$(thinking_key_for "$platform" "$role")
  if [ -n "$thinking_key" ]; then
    thinking_current=$(get_config "$thinking_key" "$(thinking_default_for "$platform" "$role")")
    prompt_thinking_value "$platform" "$role" "$thinking_current"
    PROMPT_THINKING_VALUE=$PROMPT_VALUE
  else
    PROMPT_THINKING_VALUE=
  fi
}

prompt_thinking_value() {
  platform=$1
  role=$2
  current=$3
  case "$platform" in
    opencode)
      prompt_option "$platform $role thinking variant" "$current" \
        minimal low medium high max
      ;;
    claude)
      prompt_option "$platform $role thinking effort" "$current" \
        low medium high xhigh max
      ;;
    codex)
      prompt_option "$platform $role thinking effort" "$current" \
        minimal low medium high xhigh
      ;;
    cursor)
      printf 'Cursor %s thinking is controlled by the active Cursor model.\n' "$role"
      PROMPT_VALUE=$current
      ;;
    *) die "unknown platform: $platform" ;;
  esac
}

configure_models_interactive() {
  for platform in opencode claude codex cursor; do
    case "$platform" in
      opencode) enabled=$ENABLE_OPENCODE ;;
      claude) enabled=$ENABLE_CLAUDE ;;
      codex) enabled=$ENABLE_CODEX ;;
      cursor) enabled=$ENABLE_CURSOR ;;
    esac
    [ "$enabled" = 1 ] || continue

    printf '\nConfigure models and thinking for %s.\n' "$platform"
    for role in resolver designer design-qa developer; do
      model_key=$(model_key_for "$platform" "$role")
      model_current=$(get_config "$model_key" "$(model_default_for "$platform" "$role")")
      prompt_model_value "$platform" "$role" "$model_current"
      set_config "$model_key" "$PROMPT_MODEL_VALUE"
      thinking_key=$(thinking_key_for "$platform" "$role")
      if [ -n "$thinking_key" ]; then
        set_config "$thinking_key" "$PROMPT_THINKING_VALUE"
      fi
    done
  done
}

persist_selection() {
  [ "$PERSIST_SELECTION" = 1 ] || return 0
  set_config ENABLE_OPENCODE "$ENABLE_OPENCODE"
  set_config ENABLE_CLAUDE "$ENABLE_CLAUDE"
  set_config ENABLE_CODEX "$ENABLE_CODEX"
  set_config ENABLE_CURSOR "$ENABLE_CURSOR"
  set_config MCP_LINEAR_ENABLED "$MCP_LINEAR_ENABLED"
  set_config MCP_TRELLO_ENABLED "$MCP_TRELLO_ENABLED"
  set_config MCP_LINEAR_NAME "$MCP_LINEAR_NAME"
  set_config MCP_LINEAR_URL "$MCP_LINEAR_URL"
  set_config MCP_TRELLO_NAME "$MCP_TRELLO_NAME"
  set_config MCP_TRELLO_URL "$MCP_TRELLO_URL"
  set_config SPECS_REPOSITORY "$SPECS_REPOSITORY"
  set_config SPECS_REPOSITORY_BASE_BRANCH "$SPECS_REPOSITORY_BASE_BRANCH"
}

render_opencode() {
  role=$1
  output=$2
  description=$(description_for "$role")

  case "$role" in
    resolver) model=$(get_config OPENCODE_RESOLVER_MODEL ''); variant=$(get_config OPENCODE_RESOLVER_VARIANT 'max'); mode='primary'; color='primary' ;;
    designer) model=$(get_config OPENCODE_DESIGNER_MODEL ''); variant=$(get_config OPENCODE_DESIGNER_VARIANT 'high'); mode='subagent'; color='accent' ;;
    design-qa) model=$(get_config OPENCODE_DESIGN_QA_MODEL ''); variant=$(get_config OPENCODE_DESIGN_QA_VARIANT 'high'); mode='subagent'; color='accent' ;;
    developer) model=$(get_config OPENCODE_DEVELOPER_MODEL ''); variant=$(get_config OPENCODE_DEVELOPER_VARIANT 'high'); mode='subagent'; color='success' ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf '%s\n' '---'
    printf 'description: %s\n' "$description"
    [ -n "$model" ] && printf 'model: %s\n' "$model"
    printf 'variant: %s\n' "$variant"
    printf 'mode: %s\n' "$mode"
    printf 'color: %s\n' "$color"
    printf '%s\n' 'permission:'
    case "$role" in
      resolver)
        printf '%s\n' '  edit: allow' '  skill: allow' '  question: allow' '  todowrite: allow' '  bash:' '    "*": ask' '    "openspec *": allow' '    "git status *": allow' '    "git diff *": allow' '    "git log *": allow' '    "git branch *": allow' '    "git checkout *": allow' '    "git worktree *": allow' '    "git -C *": allow' '    "git add *": allow' '    "git commit *": allow' '    "git push *": allow' '    "gh pr *": allow' '    "gh repo *": allow' '  task:' '    "*": deny' '    designer: allow' '    design-qa: allow' '    developer: allow' '    explore: allow'
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
    resolver) model=$(get_config CLAUDE_RESOLVER_MODEL ''); effort=$(get_config CLAUDE_RESOLVER_EFFORT 'high'); tools='' ;;
    designer) model=$(get_config CLAUDE_DESIGNER_MODEL ''); effort=$(get_config CLAUDE_DESIGNER_EFFORT 'high'); tools='Read, Grep, Glob, Write' ;;
    design-qa) model=$(get_config CLAUDE_DESIGN_QA_MODEL ''); effort=$(get_config CLAUDE_DESIGN_QA_EFFORT 'high'); tools='Read, Grep, Glob' ;;
    developer) model=$(get_config CLAUDE_DEVELOPER_MODEL ''); effort=$(get_config CLAUDE_DEVELOPER_EFFORT 'high'); tools='Read, Grep, Glob, Edit, Write, Bash' ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf '%s\n' '---' "name: $role" "description: $description"
    [ -n "$model" ] && printf 'model: %s\n' "$model"
    printf 'effort: %s\n' "$effort"
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
    resolver) model=$(get_config CODEX_RESOLVER_MODEL ''); effort=$(get_config CODEX_RESOLVER_EFFORT 'xhigh') ;;
    designer) model=$(get_config CODEX_DESIGNER_MODEL ''); effort=$(get_config CODEX_DESIGNER_EFFORT 'xhigh') ;;
    design-qa) model=$(get_config CODEX_DESIGN_QA_MODEL ''); effort=$(get_config CODEX_DESIGN_QA_EFFORT 'xhigh') ;;
    developer) model=$(get_config CODEX_DEVELOPER_MODEL ''); effort=$(get_config CODEX_DEVELOPER_EFFORT 'high') ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf 'name = "%s"\n' "$role"
    printf 'description = "%s"\n' "$description"
    [ -n "$model" ] && printf 'model = "%s"\n' "$model"
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
    resolver) model=$(get_config CURSOR_RESOLVER_MODEL ''); readonly=false ;;
    designer) model=$(get_config CURSOR_DESIGNER_MODEL ''); readonly=false ;;
    design-qa) model=$(get_config CURSOR_DESIGN_QA_MODEL ''); readonly=true ;;
    developer) model=$(get_config CURSOR_DEVELOPER_MODEL ''); readonly=false ;;
    *) die "unknown role: $role" ;;
  esac

  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$role"
    printf 'description: %s\n' "$description"
    [ -n "$model" ] && printf 'model: %s\n' "$model"
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
  {
    printf '%s\n' '# Project-local Codex configuration generated by setup-agent-stack.sh.'
    printf '%s\n' '# This file does not contain credentials or global settings.'
    printf '%s\n' '' '[agents]'
    printf '%s\n' 'enabled = true' "max_concurrent_threads_per_session = $max_threads"
    if [ "$MCP_LINEAR_ENABLED" = 1 ]; then
      printf '%s\n' '' "[mcp_servers.$MCP_LINEAR_NAME]"
      printf '%s\n' "url = \"$MCP_LINEAR_URL\""
    fi
    if [ "$MCP_TRELLO_ENABLED" = 1 ]; then
      printf '%s\n' '' "[mcp_servers.$MCP_TRELLO_NAME]"
      printf '%s\n' "url = \"$MCP_TRELLO_URL\""
    fi
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
requirements, OpenSpec artifacts, delegation, evidence, Linear
synchronization, and GitHub delivery. You never write implementation code
yourself. You specify, delegate, review, publish, and close.

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
Once the required answers are available, continue without asking the user to
review or approve the OpenSpec artifacts.

## 2.1 Task status

For a linked Linear task, update its state through the connected Linear MCP:

1. Once intake and clarification are complete and work is starting, set the
   task to `TASK_STATE_IN_PROGRESS` from `.agent-stack/config.conf` (default
   `In Progress`). Record the state change in the pipeline ledger.
2. After every affected implementation repository has a pushed branch and an
   open PR, set the task to `TASK_STATE_IN_PR` (default `In PR`). Record every
   PR URL and the state change.
3. Do not mark the task completed merely because a PR exists. Keep it `In PR`
   until the project's merge/closeout policy says it is complete. If either
   configured state does not exist for the team, stop and ask the user which
   team state to use instead of silently substituting another state.

## 3. Branch setup

Identify affected Git repositories and paths from the project instructions and
the request. Do not assume a monorepo or fixed directory names.

For each affected repository:

1. Run `git status --porcelain`.
2. Determine the base branch. An explicitly supplied issue, dependency, or
   parent branch wins over the repository default branch.
3. Ensure the repository has an ignored `<repo>/.worktrees/` directory. Add
   `.worktrees/` to that repository's `.gitignore` if it is missing, preserving
   all existing entries.
4. Create or reuse a dedicated worktree at
   `<repo>/.worktrees/<branch-slug>`, with the implementation branch created
   from the selected base branch. Never place a worktree in `/tmp`, beside the
   repository, or in the user's home directory.
5. Leave unrelated dirty changes in the original checkout untouched. Do not
   silently include them in the implementation worktree.

Use the issue branch name when available; otherwise use the project-approved
fallback or the OpenSpec change name. Record the base branch, implementation
branch, and worktree path in the delegation contract. The worktree strategy is
mandatory.

If the selected base branch is another feature branch, retain that branch as
the PR base. This is a stacked PR: do not silently retarget it to `main`.

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

Do not pause for user review after the artifacts are complete. Immediately
delegate the finalized change to `developer` in the same run.

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
- explicit instruction to work only in the supplied `.worktrees/` path;
- explicit instruction to return to the resolver only.

The delegation contract supersedes conflicting skill pause rules. The resolver
must make this delegation immediately after finalizing the required specs; no
spec-review approval gate is allowed.

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
2. Publish the finalized OpenSpec change to the configured specs repository:
   - Read `SPECS_REPOSITORY` and `SPECS_REPOSITORY_BASE_BRANCH` from the
     consuming project's `.agent-stack/config.conf`. `SPECS_REPOSITORY` is a
     GitHub `owner/repo` value and must be configured during installation or
     agent setup. If it is missing, stop finalization and ask the user to
     configure it; never silently skip the upload.
   - Use a local clone of that repository and keep its worktree under the
     specs repository's `.worktrees/` directory. Ensure `.worktrees/` is
     ignored before creating the worktree.
   - Copy the complete finalized `openspec/changes/<change-name>/` directory
     into the same path in the specs repository. Do not delete or rewrite
     unrelated specs.
   - Create a specs branch from `SPECS_REPOSITORY_BASE_BRANCH`, commit only
     the finalized change, push it, and create a PR against that exact base.
     Record the specs PR URL.
3. Follow the project's archive command or `/opsx-archive` workflow when
   configured; completed changes must not remain silently active.
4. Publish the implementation branch for every affected code repository:
   - Commit the verified scoped changes in the supplied worktree, push the
     branch to its GitHub remote, and create a PR with `gh pr create`.
   - Use the recorded base branch in `--base`. If it is another feature branch,
     create a stacked PR against that branch and record the parent PR URL when
     available. Never default a stacked PR to `main`.
   - If a PR already exists for the branch, update it instead of creating a
     duplicate. Do not merge automatically.
   - Record every implementation PR URL, base branch, head branch, worktree,
     verification result, and specs PR URL in the pipeline ledger.
5. After the implementation PRs are created, set the linked task to
   `TASK_STATE_IN_PR` through the connected Linear MCP before final reporting.
6. Determine the Linear project name from the linked issue. Use the connected
   Linear MCP to attach a document titled
   `Spec: <linear-project-name> — <change-name>`. The document content MUST
   begin with `Project: <linear-project-name>` and include the issue, change, branch/worktree,
   verification evidence, and corrective rounds.
7. Only when the PRs are merged and project policy requires it, update the
   linked Linear issue to its completed state and add the closing evidence
   comment through the connected Linear MCP. An open PR remains `In PR`.
8. Remaining work becomes a new issue or explicitly approved follow-up, not a
   silent `*-followup` change.
9. Append the closing row to the ledger and summarize scope, evidence,
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
2. If a branch/worktree is provided, work only in that directory before
   editing. Resolver-provided worktrees live under the repository's
   `.worktrees/` directory.
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
- Leave commit, push, and PR creation to the resolver's closeout workflow unless
  the delegation contract explicitly assigns that delivery action to you.
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

# Optional MCP integrations registered by the bootstrap for every enabled
# platform. Trello is opt-in by default; the interactive wizard can change
# either selection.
MCP_LINEAR_ENABLED=1
MCP_LINEAR_NAME=linear
MCP_LINEAR_URL=https://mcp.linear.app/mcp
MCP_TRELLO_ENABLED=0
MCP_TRELLO_NAME=trello
MCP_TRELLO_URL=https://mcp.trello.com/mcp

# Finalized OpenSpec publication. Setup requires a GitHub owner/repo here or
# through --specs-repository so the resolver can upload completed changes.
SPECS_REPOSITORY=
SPECS_REPOSITORY_BASE_BRANCH=main
TASK_STATE_IN_PROGRESS=In Progress
TASK_STATE_IN_PR=In PR

# OpenCode model pinning (provider/model + variant).
OPENCODE_RESOLVER_MODEL=
OPENCODE_RESOLVER_VARIANT=max
OPENCODE_DESIGNER_MODEL=
OPENCODE_DESIGNER_VARIANT=max
OPENCODE_DESIGN_QA_MODEL=
OPENCODE_DESIGN_QA_VARIANT=max
OPENCODE_DEVELOPER_MODEL=
OPENCODE_DEVELOPER_VARIANT=high

# Claude Code mirrors (Claude model aliases; OpenCode provider IDs are unsupported).
CLAUDE_RESOLVER_MODEL=
CLAUDE_RESOLVER_EFFORT=high
CLAUDE_DESIGNER_MODEL=
CLAUDE_DESIGNER_EFFORT=high
CLAUDE_DESIGN_QA_MODEL=
CLAUDE_DESIGN_QA_EFFORT=high
CLAUDE_DEVELOPER_MODEL=
CLAUDE_DEVELOPER_EFFORT=high

# Codex custom agents (Codex model IDs + reasoning effort: minimal|low|medium|high|xhigh).
CODEX_RESOLVER_MODEL=
CODEX_RESOLVER_EFFORT=xhigh
CODEX_DESIGNER_MODEL=
CODEX_DESIGNER_EFFORT=xhigh
CODEX_DESIGN_QA_MODEL=
CODEX_DESIGN_QA_EFFORT=xhigh
CODEX_DEVELOPER_MODEL=
CODEX_DEVELOPER_EFFORT=high

# Cursor subagents (Cursor model IDs).
CURSOR_RESOLVER_MODEL=
CURSOR_DESIGNER_MODEL=
CURSOR_DESIGN_QA_MODEL=
CURSOR_DEVELOPER_MODEL=
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

ensure_config() {
  ensure_dir "$ROOT/.agent-stack"

  if [ -f "$KIT_ROOT/.agent-stack/defaults.conf" ]; then
    copy_if_missing "$KIT_ROOT/.agent-stack/defaults.conf" "$ROOT/.agent-stack/config.conf"
  elif [ ! -f "$ROOT/.agent-stack/config.conf" ]; then
    write_embedded_defaults "$ROOT/.agent-stack/config.conf"
    printf 'created %s\n' "$ROOT/.agent-stack/config.conf"
  fi
}

ensure_worktree_ignore() {
  ignore_file=$ROOT/.gitignore
  ensure_dir "$ROOT/.worktrees"

  if [ -f "$ignore_file" ] && awk '$0 ~ /^[[:space:]]*(\/)?\.worktrees\/?[[:space:]]*(#.*)?$/ { found=1; exit } END { exit(found ? 0 : 1) }' "$ignore_file"; then
    return 0
  fi

  temporary=$(mktemp "$ROOT/.agent-stack/.gitignore.XXXXXX")
  if [ -f "$ignore_file" ]; then
    cat "$ignore_file" > "$temporary"
  else
    : > "$temporary"
  fi
  printf '%s\n' '' '# Agent stack worktrees' '.worktrees/' >> "$temporary"
  mv "$temporary" "$ignore_file"
  printf '%s\n' "updated $ignore_file with .worktrees/"
}

ensure_scaffolds() {
  ensure_config
  ensure_worktree_ignore

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
  command -v node >/dev/null 2>&1 || die 'node is required to merge MCP config'
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

ensure_mcp_server() {
  server=$1
  case "$server" in
    linear)
      name=$MCP_LINEAR_NAME
      url=$MCP_LINEAR_URL
      ;;
    trello)
      name=$MCP_TRELLO_NAME
      url=$MCP_TRELLO_URL
      ;;
    *) die "unknown MCP server: $server" ;;
  esac

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

ensure_mcp_config() {
  if [ "$MCP_LINEAR_ENABLED" = 1 ]; then
    ensure_mcp_server linear
  fi
  if [ "$MCP_TRELLO_ENABLED" = 1 ]; then
    ensure_mcp_server trello
  fi
}

install_codex_bridge() {
  bridge_start='<!-- agent-stack:codex-bridge:start -->'
  bridge_end='<!-- agent-stack:codex-bridge:end -->'
  bridge_text=$(cat <<'EOF'
<!-- agent-stack:codex-bridge:start -->
## Agent Stack UX/UI Guidance

For user-facing UX/UI work, read the nearest `UX_AGENTS.md` and `UI_AGENTS.md`.
These are the only project-specific UX/UI context files. Use the configured
project-tracking MCP when one is enabled and derive project metadata from the
linked issue.
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
    --mcp)
      [ "$#" -gt 1 ] || die '--mcp requires none, linear, trello, or both'
      MCP_ARG=$2
      EXPLICIT_MCP=1
      shift
      ;;
    --specs-repository|--specs-repo)
      [ "$#" -gt 1 ] || die '--specs-repository requires owner/repo'
      SPECS_REPOSITORY_ARG=$2
      shift
      ;;
    --specs-repository=*|--specs-repo=*)
      SPECS_REPOSITORY_ARG=${1#*=}
      ;;
    --specs-base-branch)
      [ "$#" -gt 1 ] || die '--specs-base-branch requires a branch name'
      SPECS_REPOSITORY_BASE_BRANCH_ARG=$2
      shift
      ;;
    --specs-base-branch=*)
      SPECS_REPOSITORY_BASE_BRANCH_ARG=${1#*=}
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
    resolve_mcp
    resolve_delivery_config
    if [ "$INTERACTIVE_WIZARD" = 1 ]; then
      configure_delivery_interactive
      configure_models_interactive
    fi
    require_specs_repository
    persist_selection
    if [ "$INSTALL_CODEX_BRIDGE" -eq 1 ]; then
      install_codex_bridge
    fi
    render_platform_outputs sync
    ensure_mcp_config
    ;;
  sync)
    ensure_config
    ensure_worktree_ignore
    resolve_mcp
    resolve_delivery_config
    ensure_role_sources
    if [ "$INTERACTIVE_WIZARD" = 1 ]; then
      configure_delivery_interactive
      configure_models_interactive
    fi
    require_specs_repository
    persist_selection
    render_platform_outputs sync
    if [ "$INSTALL_CODEX_BRIDGE" -eq 1 ]; then
      install_codex_bridge
    fi
    ensure_mcp_config
    ;;
  check)
    ROLE_DIR=$ROOT/.agent-stack/roles
    [ -d "$ROLE_DIR" ] || die "missing role source directory: $ROLE_DIR"
    [ -f "$CONFIG_FILE" ] || die "missing config: $CONFIG_FILE"
    resolve_mcp
    resolve_delivery_config
    require_specs_repository
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
