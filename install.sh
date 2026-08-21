#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage:
  install.sh --path=/absolute/path/to/project [options]

The target path must already exist. Options after --path are passed to the
agent-stack setup script, including --platforms, --mcp, --select, and
--specs-repository.
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
