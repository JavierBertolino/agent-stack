#!/usr/bin/env sh
# install.sh — Agent Stack installer.
#
# Public install (no checkout needed):
#   curl -fsSL https://github.com/JavierBertolino/agent-stack/releases/latest/download/install.sh | sh
#   cd my-project
#   astack init
#   astack doctor
#
# From a checkout (development / offline):
#   ./install.sh --path=/absolute/path/to/project [setup options]
#   ./install.sh --global [--prefix DIR] [--version VER]
#
# Env overrides:
#   ASTACK_REPO          GitHub repository (default: JavierBertolino/agent-stack).
#   ASTACK_VERSION       Pin a release (default: latest; never main).
#   ASTACK_RELEASE_BASE  Local directory with astack.tar.gz + sha256 (tests).

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO=${ASTACK_REPO:-JavierBertolino/agent-stack}

usage() {
  cat <<'EOF'
Usage:
  install.sh [--prefix DIR] [--version VER]
  install.sh --path=/absolute/path/to/project [options]
  install.sh --global [--prefix DIR] [--version VER]

With no mode flag, install.sh downloads the latest versioned GitHub
Release artifact (never main), verifies its SHA-256 checksum, and performs
a versioned user-level install:

  curl -fsSL https://github.com/JavierBertolino/agent-stack/releases/latest/download/install.sh | sh

--path installs into an existing project directory using this checkout as
the kit root. Options after --path are passed to the setup script,
including --platforms, --mcp, and --specs-repository (mirror mode only;
local mode needs no specs repository).

--global installs the kit versioned under <prefix>/share/astack
(default $HOME/.local) and puts the `astack` executable on <prefix>/bin,
so any project directory can run `astack init` directly.
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

detect_platform() {
  os=$(uname -s 2>/dev/null || printf 'unknown')
  arch=$(uname -m 2>/dev/null || printf 'unknown')
  printf '%s/%s\n' "$os" "$arch"
}

latest_release_tag() {
  if [ -n "${ASTACK_RELEASE_BASE:-}" ]; then
    [ -f "$ASTACK_RELEASE_BASE/VERSION" ] \
      || path_error "release base has no VERSION file: $ASTACK_RELEASE_BASE"
    tag=$(awk 'NR == 1 { print $1; exit }' "$ASTACK_RELEASE_BASE/VERSION")
    [ -n "$tag" ] || path_error "release base VERSION is empty"
    case "$tag" in
      v*) printf '%s\n' "$tag" ;;
      *) printf 'v%s\n' "$tag" ;;
    esac
    return 0
  fi
  command -v curl >/dev/null 2>&1 || path_error 'curl is required to download Agent Stack'
  response=$(curl -fsSL --max-time 20 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null) \
    || path_error "could not resolve the latest release (check your network)"
  tag=$(printf '%s' "$response" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/') || true
  [ -n "$tag" ] || path_error 'could not parse the latest release tag'
  printf '%s\n' "$tag"
}

strip_v() {
  case "$1" in
    v*) printf '%s\n' "${1#v}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# install_versioned SOURCE_DIR VERSION PREFIX
install_versioned() {
  source_dir=$1
  version=$2
  prefix=$3

  base=$prefix/share/astack
  target=$base/versions/$version
  mkdir -p "$base/versions" "$prefix/bin"

  if [ -d "$target" ]; then
    rm -rf "$target"
  fi
  mkdir -p "$target"
  for entry in scripts .agent-stack VERSION; do
    [ -e "$source_dir/$entry" ] || path_error "kit source is missing $entry: $source_dir"
    cp -r "$source_dir/$entry" "$target/"
  done
  for optional in LICENSE README.md CHANGELOG.md; do
    [ -e "$source_dir/$optional" ] && cp "$source_dir/$optional" "$target/"
  done

  # Sanity check before switching.
  for script in setup-agent-stack.sh doctor.sh upgrade-agent-stack.sh update-agent-stack.sh astack; do
    [ -f "$target/scripts/$script" ] || path_error "kit source is missing scripts/$script"
    sh -n "$target/scripts/$script" || path_error "sanity check failed for scripts/$script"
  done

  # Atomically switch current. `mv` over an existing symlink-to-directory
  # would move the new link inside the target, so remove first, then move.
  ln -sfn "versions/$version" "$base/current.new"
  rm -f "$base/current"
  mv -f "$base/current.new" "$base/current"

  # The real executable is astack. agent-stack stays as an unadvertised
  # backwards-compatibility alias.
  # shellcheck disable=SC2086
  sed "s|^SHARE=\"@SHARE@\"$|SHARE=\"$base\"|" \
    "$target/scripts/astack" > "$prefix/bin/astack"
  chmod +x "$prefix/bin/astack"
  ln -sf astack "$prefix/bin/agent-stack"

  printf '\n%s\n' "Agent Stack v$version installed successfully."
  printf '\n%s\n' 'Next:'
  printf '\n%s\n' '  cd your-project'
  printf '%s\n' '  astack init'
  printf '\n%s\n' 'Verify your environment at any time with:'
  printf '\n%s\n' '  astack doctor'
  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *)
      printf '\nnote: %s is not on PATH; add this to your shell profile:\n' "$prefix/bin" >&2
      printf '  export PATH="%s:$PATH"\n' "$prefix/bin" >&2
      ;;
  esac
}

MODE=public
TARGET=
PREFIX=$HOME/.local
PINNED=${ASTACK_VERSION:-}
SETUP_ARGS=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --path=*) MODE=path; TARGET=${1#--path=}; shift ;;
    --path)
      [ "$#" -gt 1 ] || path_error "--path requires a value (use --path=/absolute/path/to/project)"
      MODE=path; TARGET=$2; shift 2 ;;
    --global) MODE=global; shift ;;
    --prefix=*) PREFIX=${1#--prefix=}; shift ;;
    --prefix) path_error "--prefix requires a value (use --prefix=DIR)" ;;
    --version=*) PINNED=${1#--version=}; shift ;;
    -h|--help) usage; exit 0 ;;
    --*)
      if [ "$MODE" = path ]; then
        SETUP_ARGS="$SETUP_ARGS $1"; shift
      else
        path_error "unknown option: $1"
      fi
      ;;
    *)
      if [ "$MODE" = path ]; then
        SETUP_ARGS="$SETUP_ARGS $1"; shift
      else
        path_error "unknown argument: $1 (see install.sh --help)"
      fi
      ;;
  esac
done

case "$MODE" in
  path)
    TARGET=$(normalize_target "$TARGET")
    [ -d "$TARGET" ] || path_error "target directory does not exist: $TARGET"
    # shellcheck disable=SC2086
    exec sh "$SCRIPT_DIR/scripts/setup-agent-stack.sh" init \
      --root "$TARGET" \
      --kit-root "$SCRIPT_DIR" $SETUP_ARGS
    ;;
  global)
    case "$PREFIX" in
      /*) ;;
      *) path_error "--prefix must be absolute: $PREFIX" ;;
    esac
    if [ -n "$PINNED" ]; then
      version=$(strip_v "$PINNED")
    elif [ -f "$SCRIPT_DIR/VERSION" ]; then
      version=$(awk 'NR == 1 { print $1; exit }' "$SCRIPT_DIR/VERSION")
    else
      version=$(awk -F= '$1 == "AGENT_STACK_VERSION" { print $2; exit }' "$SCRIPT_DIR/.agent-stack/defaults.conf")
    fi
    [ -n "$version" ] || path_error 'could not determine the kit version'
    install_versioned "$SCRIPT_DIR" "$version" "$PREFIX"
    exit 0
    ;;
  public)
    case "$PREFIX" in
      /*) ;;
      *) path_error "--prefix must be absolute: $PREFIX" ;;
    esac
    [ -z "$SETUP_ARGS" ] || path_error "unknown argument for public install:$SETUP_ARGS (see install.sh --help)"
    printf '%s\n' 'Agent Stack installer'
    printf 'Platform: %s\n' "$(detect_platform)"
    if [ -n "$PINNED" ]; then
      case "$PINNED" in
        v*) TAG=$PINNED ;;
        *) TAG=v$PINNED ;;
      esac
    else
      printf 'Resolving the latest release...\n'
      TAG=$(latest_release_tag)
    fi
    version=$(strip_v "$TAG")
    printf 'Release: %s\n' "$TAG"
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/astack-install.XXXXXX")
    trap 'rm -rf "$WORK"' EXIT INT TERM
    if [ -n "${ASTACK_RELEASE_BASE:-}" ]; then
      cp "$ASTACK_RELEASE_BASE/astack.tar.gz" "$WORK/astack.tar.gz" \
        || path_error "release base has no astack.tar.gz"
      cp "$ASTACK_RELEASE_BASE/astack.tar.gz.sha256" "$WORK/astack.tar.gz.sha256" \
        || path_error "release base has no astack.tar.gz.sha256"
    else
      printf 'Downloading Agent Stack %s...\n' "$version"
      curl -fsSL --max-time 120 \
        "https://github.com/$REPO/releases/download/$TAG/astack.tar.gz" \
        -o "$WORK/astack.tar.gz" || path_error "download failed for $TAG"
      curl -fsSL --max-time 60 \
        "https://github.com/$REPO/releases/download/$TAG/astack.tar.gz.sha256" \
        -o "$WORK/astack.tar.gz.sha256" || path_error "checksum download failed for $TAG"
    fi
    printf 'Verifying checksum...\n'
    (cd "$WORK" && {
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c astack.tar.gz.sha256 >/dev/null 2>&1
      else
        shasum -a 256 -c astack.tar.gz.sha256 >/dev/null 2>&1
      fi
    }) || path_error 'checksum verification failed; aborting install'
    printf 'Installing...\n'
    mkdir -p "$WORK/kit"
    tar -xzf "$WORK/astack.tar.gz" -C "$WORK/kit" || path_error 'could not extract the release archive'
    install_versioned "$WORK/kit" "$version" "$PREFIX"
    trap - EXIT INT TERM
    rm -rf "$WORK"
    exit 0
    ;;
esac
