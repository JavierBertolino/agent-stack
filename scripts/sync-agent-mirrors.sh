#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=$(pwd)
COMMAND=sync

if [ "${1:-}" = "--check" ]; then
  COMMAND=check
  shift
fi

exec sh "$SCRIPT_DIR/setup-agent-stack.sh" "$COMMAND" \
  --root "$ROOT" \
  --kit-root "$KIT_ROOT" \
  --claude-only "$@"
