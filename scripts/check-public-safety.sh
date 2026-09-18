#!/usr/bin/env sh
# check-public-safety.sh — fail on accidental private references in the
# public tree: hardcoded home paths, internal names, credential literals,
# private-repo wording, and primary `agent-stack` commands in public docs.
#
# The canonical repository owner (JavierBertolino) is always allowed where
# it legitimately identifies the project. Usage:
#   scripts/check-public-safety.sh [--kit-root PATH]
set -eu

KIT_ROOT=$(pwd)
for arg in "$@"; do
  case "$arg" in
    --kit-root=*) KIT_ROOT=${arg#--kit-root=} ;;
    --kit-root) shift; KIT_ROOT=$1 ;;
    -h|--help) printf '%s\n' "Usage: check-public-safety.sh [--kit-root PATH]"; exit 0 ;;
  esac
done

FAIL=0
report() { printf 'public-safety: %s\n' "$1" >&2; FAIL=1; }

if [ -d "$KIT_ROOT/.git" ]; then
  FILES=$(cd "$KIT_ROOT" && git ls-files)
else
  FILES=$(cd "$KIT_ROOT" && find . -path ./.git -prune -o -path ./dist -prune -o -type f -print | sed 's|^\./||')
fi

scan() {
  icase=
  if [ "${1:-}" = "-i" ]; then icase=-i; shift; fi
  pattern=$1
  label=$2
  hit=0
  for f in $FILES; do
    [ -f "$KIT_ROOT/$f" ] || continue
    case "$f" in
      scripts/check-public-safety.sh) continue ;;
    esac
    # shellcheck disable=SC2086
    out=$(grep -E -n $icase -e "$pattern" "$KIT_ROOT/$f" 2>/dev/null | grep -v -e 'JavierBertolino/agent-stack' -e 'share/agent-stack' || true)
    if [ -n "$out" ]; then
      printf '%s\n' "$out" | while IFS= read -r line; do
        printf 'public-safety [%s]: %s:%s\n' "$label" "$f" "$line" >&2
      done
      hit=1
    fi
  done
  if [ "$hit" = 1 ]; then FAIL=1; fi
}

# Hardcoded home directories (portable $HOME / ~ forms are fine).
scan '/Users/' 'macos-home-path'
scan 'C:\\Users|C:/Users' 'windows-home-path'
scan '/home/[a-zA-Z0-9_.-]+/' 'linux-home-path'

# Internal / project-specific names (case-insensitive).
scan -i 'opsia|stock[- ]?manager|binagora|hornero|lcvista' 'private-name'

# Credential literals assigned in source (placeholders stay allowed).
scan '(API_KEY|SECRET|PASSWORD|TOKEN)[=:][ ]*["'"'"']?[A-Za-z0-9_.$/-]{16,}["'"'"']?' 'possible-secret'

# Private-repository distribution wording.
scan 'gh auth login' 'private-distro'
scan '[Gg]ranted access' 'private-distro'
scan '[Pp]rivate repository access' 'private-distro'

# Primary `agent-stack` commands must not appear in public docs; the
# canonical command is `astack`. Matches lines like `agent-stack init`
# while allowing paths (.agent-stack/, share/agent-stack), the tarball
# name, and the alias discussion itself.
doc_hits=0
for f in README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md docs/*.md .github/PULL_REQUEST_TEMPLATE.md; do
  [ -f "$KIT_ROOT/$f" ] || continue
  out=$(grep -E -n -e '(^|[^a-zA-Z0-9_./-])agent-stack +(init|sync|check|doctor|auth|update|upgrade|prune|run-state|validate|--version|--help)' "$KIT_ROOT/$f" 2>/dev/null | grep -v -i -e 'alias' -e 'backwards-compat' || true)
  if [ -n "$out" ]; then
    printf '%s\n' "$out" | while IFS= read -r line; do
      printf 'public-safety [legacy-command]: %s:%s\n' "$f" "$line" >&2
    done
    doc_hits=1
  fi
done
if [ "$doc_hits" = 1 ]; then FAIL=1; fi

if [ "$FAIL" -ne 0 ]; then
  report "private references found (see lines above)"
  exit 1
fi
printf 'public-safety: no private references found\n'
