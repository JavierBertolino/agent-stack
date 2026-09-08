#!/usr/bin/env sh
# Contract tests: fixtures validate against the JSON schemas, and invalid
# fixtures are rejected.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
check_ok() {
  if python3 "$KIT_ROOT/scripts/validate-contracts.py" --kit-root "$KIT_ROOT" --type "$1" "$2" >/dev/null 2>&1; then
    :
  else
    printf 'FAIL expected valid: %s %s\n' "$1" "$2" >&2; FAIL=1
  fi
}
check_bad() {
  if python3 "$KIT_ROOT/scripts/validate-contracts.py" --kit-root "$KIT_ROOT" --type "$1" "$2" >/dev/null 2>&1; then
    printf 'FAIL expected invalid: %s %s\n' "$1" "$2" >&2; FAIL=1
  fi
}
check_ok handoff "$KIT_ROOT/tests/fixtures/handoff-valid.json"
check_bad handoff "$KIT_ROOT/tests/fixtures/handoff-invalid.json"
check_ok report "$KIT_ROOT/tests/fixtures/report-valid.json"
check_bad report "$KIT_ROOT/tests/fixtures/report-invalid.json"
check_ok run-state "$KIT_ROOT/tests/fixtures/run-state-valid.json"
check_bad run-state "$KIT_ROOT/tests/fixtures/run-state-invalid.json"
check_ok event "$KIT_ROOT/tests/fixtures/events-valid.jsonl"
check_bad event "$KIT_ROOT/tests/fixtures/events-invalid.jsonl"
[ "$FAIL" -eq 0 ]
