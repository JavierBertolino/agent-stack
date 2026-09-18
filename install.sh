#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage:
  install.sh --path=/absolute/path/to/project [options]
  install.sh --global [--prefix DIR]

The target path must already exist. Options after --path are passed to the
agent-stack setup script, including --platforms, --mcp, --select, and
--specs-repository (sets SPECS_REPOSITORY and mirror publication mode;
local mode needs no specs repository).

--global installs the kit to <prefix>/share/agent-stack (default
$HOME/.local) and puts an `agent-stack` dispatcher on <prefix>/bin, so
any project directory can run `agent-stack init` directly.
EOF
}

path_error() {
  printf '%s\n' "install.sh: $*" >&2
  exit 2
}

normalize_target() {
  case "$1" in
    /*)
      printf '%s\n' "$1"
      ;;
    [A-Za-z]:/*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
      elif command -v wslpath >/dev/null 2>&1; then
        wslpath -u "$1"
      else
        path_error "cannot convert Windows path without cygpath or wslpath: $1"
      fi
      ;;
    *)
      path_error "--path must be absolute: $1"
      ;;
  esac
}

case "${1:-}" in
  --global)
    shift
    PREFIX=$HOME/.local
    for arg in "$@"; do
      case "$arg" in
        --prefix=*) PREFIX=${arg#--prefix=} ;;
        --prefix) path_error "--prefix requires a value (use --prefix=DIR)" ;;
        -h|--help) usage; exit 0 ;;
        *) path_error "unknown global option: $arg" ;;
      esac
    done
    case "$PREFIX" in
      /*) ;;
      *) path_error "--prefix must be absolute: $PREFIX" ;;
    esac
    SHARE=$PREFIX/share/agent-stack
    mkdir -p "$SHARE" "$PREFIX/bin"
    cp -r "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/.agent-stack" "$SHARE/"
    # shellcheck disable=SC2086
    sed "s|^SHARE=\"@SHARE@\"$|SHARE=\"$SHARE\"|" \
      "$SCRIPT_DIR/scripts/agent-stack" > "$PREFIX/bin/agent-stack"
    chmod +x "$PREFIX/bin/agent-stack"
    ln -sf agent-stack "$PREFIX/bin/astack"
    printf 'installed agent-stack %s to %s\n' \
      "$(awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' "$SHARE/.agent-stack/defaults.conf")" \
      "$PREFIX/bin/agent-stack"
    printf 'short alias available as %s\n' "$PREFIX/bin/astack"
    case ":$PATH:" in
      *":$PREFIX/bin:"*) ;;
      *)
        printf 'note: %s is not on PATH; add this to your shell profile:\n' "$PREFIX/bin" >&2
        printf '  export PATH="%s:$PATH"\n' "$PREFIX/bin" >&2
        ;;
    esac
    printf 'from a project directory run: agent-stack init --platforms opencode\n'
    exit 0
    ;;
  --path=*)
    TARGET=${1#--path=}
    shift
    ;;
  --path)
    [ "$#" -gt 1 ] || { usage >&2; exit 2; }
    TARGET=$2
    shift 2
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

TARGET=$(normalize_target "$TARGET")

[ -d "$TARGET" ] || {
  path_error "target directory does not exist: $TARGET"
}

exec sh "$SCRIPT_DIR/scripts/setup-agent-stack.sh" init \
  --root "$TARGET" \
  --kit-root "$SCRIPT_DIR" \
  "$@"
