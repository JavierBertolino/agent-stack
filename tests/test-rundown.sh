#!/usr/bin/env sh
# Rundown contract: the skill and the QA roles that consume its output agree
# on the output paths and the field labels the QA agents filter by.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FAIL=0
SKILL=$KIT_ROOT/.agent-stack/skills/rundown/SKILL.md
WEB=$KIT_ROOT/.agent-stack/roles/web-qa.md
MOBILE=$KIT_ROOT/.agent-stack/roles/mobile-qa.md

expect() {
  grep -qF -- "$2" "$1" || { printf 'FAIL rundown %s: missing %s\n' "$3" "$2" >&2; FAIL=1; }
}

[ -f "$SKILL" ] || { printf 'FAIL rundown skill missing\n' >&2; exit 1; }

# Both outputs are written from the same evidence.
expect "$SKILL" 'reports/rundown/<slug>.md' 'skill names the agent copy'
expect "$SKILL" 'reports/rundown/<slug>.html' 'skill names the human copy'

# Field labels the QA roles filter on exist in the Markdown format.
for label in '- Surface: web' '- Environment:' '### RD-1' '- Steps:' '- Preconditions:' \
             '- Entry:' '## Manual test cases' '## How QA agents use this file' \
             '## Features' '### F-1' '- Stage:' '## Promotions' '## Reverted'; do
  expect "$SKILL" "$label" "format label"
done

# Consumers point at the rundown and the surface they own.
expect "$WEB" 'reports/rundown/<slug>.md' 'web-qa intake'
expect "$WEB" '`Surface: web`' 'web-qa surface filter'
expect "$MOBILE" 'reports/rundown/<slug>.md' 'mobile-qa intake'
expect "$MOBILE" '`Surface: mobile`' 'mobile-qa surface filter'

# Stages are evidence-backed: every detection method is named, and an
# unconfirmed stage never rounds up to released.
for method in '`ancestry`' '`patch`' '`reference`' '`unclear`' '`partially released`'; do
  expect "$SKILL" "$method" "stage detection"
done
expect "$SKILL" 'A stage that no method confirms is `unclear`, never `released`.' 'unclear guardrail'

# Read-only on inspected repositories; the HTML stays self-contained.
expect "$SKILL" 'Never checkout, reset, stash, commit, push, or edit files' 'read-only guardrail'
expect "$SKILL" 'no external' 'self-contained HTML'

[ "$FAIL" -eq 0 ]
