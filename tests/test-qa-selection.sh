#!/usr/bin/env sh
# Role-contract assertions for the QA agents' Jev action-selection loop
# (spec: jev-action-selection). The executable validator behavior is covered
# separately in tests/test-jev.mjs; these assertions pin role integration.
#
# Assertions run against a whitespace-collapsed copy of each role so a
# sentence that wraps across lines still matches.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agent-stack-test-qasel.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

report() {
  printf 'FAIL qa-selection: %s\n' "$1" >&2
  FAIL=1
}

web="$KIT_ROOT/.agent-stack/roles/web-qa.md"
mobile="$KIT_ROOT/.agent-stack/roles/mobile-qa.md"
web_flat="$WORK/web.flat"
mobile_flat="$WORK/mobile.flat"
tr '\n' ' ' < "$web" | tr -s ' ' > "$web_flat"
tr '\n' ' ' < "$mobile" | tr -s ' ' > "$mobile_flat"

# want FILE DESCRIPTION PATTERN...
want() {
  file=$1; shift
  desc=$1; shift
  for pattern in "$@"; do
    grep -q "$pattern" "$file" || { report "$desc (missing: $pattern)"; return; }
  done
}

# --- Both roles: Jev recommends, the agent drives ------------------------
check_role() {
  flat=$1; raw=$2; name=$3; target=$4
  want "$flat" "$name lacks the advisory selection contract" \
    'Jev recommends among candidates you author'
  if grep -qi 'Jev \(executes\|drives\|clicks\|taps\)' "$raw"; then
    report "$name describes Jev as executing actions"
  fi
  want "$flat" "$name does not state Jev never drives the $target" \
    "it never drives the $target"
  want "$flat" "$name does not require loading the Jev skill" 'typesafe-jev'
  want "$flat" "$name lacks the closed candidate set rule" 'Build a closed candidate set'
  want "$flat" "$name does not require inspect_more and stop" 'inspect_more' '`stop`'
  want "$flat" "$name lacks preconditions and the closed-option boundary" 'checkable preconditions' 'open-ended'
  want "$flat" "$name lacks candidate identifiers and effects" 'opaque stable id' 'possible effects'
  want "$flat" "$name lacks the selection question builder" 'buildSelectionQuestion\|buildMobileSelectionQuestion'
  want "$flat" "$name does not use one Choice question" 'one `choice`'

  # Executable gate integration and fail-closed handling.
  want "$flat" "$name does not call the shared executable gate" 'scripts/jev/validate-action-selection.ts'
  want "$flat" "$name does not require a fresh observation" 'fresh observation'
  want "$flat" "$name does not require a passing execute result" 'status: execute' 'current candidate id'
  want "$flat" "$name omits inspect/stop semantics" '`inspect_more` means inspect' '`stop` means finish'
  want "$flat" "$name omits gate validation properties" 'probability map' 'authorization' 'JSON Pointer preconditions'
  want "$flat" "$name omits the fixed confidence threshold" 'fixed floor 0.75'
  want "$flat" "$name is not fail-closed" 'Any other result means do not act'
  want "$flat" "$name lacks an escalation path" 'escalate `UNVERIFIED`'

  want "$flat" "$name lost the one-action cadence" 'One action, one observation'
  want "$flat" "$name no longer records the trace pair" '{ action, observed }'
  want "$flat" "$name does not refresh state before re-asking" 'refresh state before asking again'
  want "$flat" "$name does not bar model-generated values" 'never supplies values'
  want "$flat" "$name does not keep selection separate from evaluation" \
    'Selection (§3) and evaluation are separate calls' 'never produces a verdict'
  want "$flat" "$name lacks the boundary-widening rule" 'never widens the'
  want "$flat" "$name lacks the data-exclusion rule" 'personal data' 'screenshots'
}

check_role "$web_flat" "$web" "web-qa.md" "browser"
check_role "$mobile_flat" "$mobile" "mobile-qa.md" "device"

# --- Evaluation question set unchanged (the regression guard) -----------
for entry in \
  'task_completed' 'action_had_visible_effect' 'error_blocked_task' \
  'business_rule_respected' 'forbidden_side_effects_avoided' \
  'state_transition_valid' 'traceability_present' \
  'one_primary_action' 'impact_before_confirm' 'copy_plain_and_actionable'; do
  grep -q "$entry" "$web" || report "web-qa dropped evaluation question $entry"
  grep -q "$entry" "$mobile" || report "mobile-qa dropped evaluation question $entry"
done
grep -q 'gesture_and_back_behaved' "$mobile" || report "mobile-qa dropped gesture_and_back_behaved"
grep -q 'persisted_after_relaunch' "$mobile" || report "mobile-qa dropped persisted_after_relaunch"
grep -q 'status_explains_next_step' "$web" || report "web-qa dropped status_explains_next_step"
grep -q 'persisted_after_reload' "$web" || report "web-qa dropped persisted_after_reload"
grep -q 'touch_targets_and_density_ok' "$mobile" || report "mobile-qa dropped touch_targets_and_density_ok"
if ! grep -q 'choice` question keyed `next_action`' "$KIT_ROOT/docs/jev.md"; then
  report 'docs/jev.md must name the required next_action selection question key'
fi

# --- Question libraries: a selection builder, not a selection question --
for lib in "$KIT_ROOT/.agent-stack/resources/web-qa/questions.ts" \
           "$KIT_ROOT/.agent-stack/resources/mobile-qa/questions-mobile.ts"; do
  want "$lib" "$(basename -- "$lib") has no selection builder" \
    'buildSelectionQuestion\|buildMobileSelectionQuestion'
done
for source in "$KIT_ROOT/.agent-stack/resources/jev/action-selection.ts" \
              "$KIT_ROOT/.agent-stack/resources/jev/validate-action-selection.ts"; do
  [ -f "$source" ] || report "shared action-selection resource missing: $source"
done
gate="$KIT_ROOT/.agent-stack/resources/jev/action-selection.ts"
for check in 'validateActionSelection' 'candidate set' 'probabilities' 'confidence' \
             'authorized' 'validatePreconditions' 'sameJson(input.submittedObservation'; do
  grep -q "$check" "$gate" || report "executable selection gate missing check: $check"
done
# The exported evaluation builders must not contain a selection question.
if sed -n '/^export function buildQuestions/,/^}/p' "$KIT_ROOT/.agent-stack/resources/web-qa/questions.ts" \
   | grep -q 'next_action'; then
  report 'buildQuestions must not emit next_action'
fi
if sed -n '/^export function buildMobileQuestions/,/^}/p' \
   "$KIT_ROOT/.agent-stack/resources/mobile-qa/questions-mobile.ts" | grep -q 'next_action'; then
  report 'buildMobileQuestions must not emit next_action'
fi

# --- Mobile prerequisites stay a numbered discovery step -----------------
if grep -q '^## 0\. Prerequisites' "$mobile"; then
  report 'mobile-qa still has a separate section 0'
fi

[ "$FAIL" -eq 0 ]
