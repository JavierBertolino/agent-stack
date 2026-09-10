#!/usr/bin/env sh
# Fixture, rendering, installer, upgrade, and contract tests for Agent Stack.
# Usage: tests/run.sh [--kit-root PATH]
# Exits 0 when every test passes, 1 otherwise. Each tests/test-*.sh is a
# file-rendering/unit test; host runtime integration is covered separately
# by the manual compatibility matrix in docs/ADAPTER_CAPABILITIES.md.
set -eu
KIT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for arg in "$@"; do
  case "$arg" in
    --kit-root=*) KIT_ROOT=${arg#--kit-root=} ;;
    --kit-root) shift; KIT_ROOT=$1 ;;
  esac
done
export KIT_ROOT
PASS=0
FAIL=0
for test in "$KIT_ROOT"/tests/test-*.sh; do
  name=$(basename -- "$test")
  if sh "$test"; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n' "$name" >&2
    FAIL=$((FAIL + 1))
  fi
done
printf 'tests: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
