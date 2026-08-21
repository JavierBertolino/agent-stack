#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
  cat <<'EOF'
Usage:
  install.sh --path=/absolute/path/to/project [options]

The target path must already exist. Options after --path are passed to the
agent-stack setup script, including --platforms, --mcp, and --select.
EOF
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

case "$TARGET" in
  /*) ;;
  *) printf '%s\n' "install.sh: --path must be absolute: $TARGET" >&2; exit 2 ;;
esac

[ -d "$TARGET" ] || {
  printf '%s\n' "install.sh: target directory does not exist: $TARGET" >&2
  exit 2
}

exec sh "$SCRIPT_DIR/scripts/setup-agent-stack.sh" init \
  --root "$TARGET" \
  --kit-root "$SCRIPT_DIR" \
  "$@"
