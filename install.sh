#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

exec sh "$SCRIPT_DIR/scripts/setup-agent-stack.sh" \
  --kit-root "$SCRIPT_DIR" \
  "$@"
