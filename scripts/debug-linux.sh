#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE=full
ASSUME_YES=false
INSPECT_SHELL=true
OPTIONAL_STEPS=''
SKIP_MANAGED_TOOLS=false
CONTAINER="dotfiles-debug-$(date +%Y%m%d-%H%M%S)-$RANDOM"

usage() {
  cat << 'EOF'
Usage: bash scripts/debug-linux.sh [options]

Run the local Linux installer in a fresh Ubuntu 24.04 container.
Keep the container and open a shell after setup for inspection.

Options:
  --profile PROFILE  core or full (default: full)
  --with STEPS       optional steps: docker,tailscale,pitchfork,t3
  --skip-managed-tools  skip the managed mise tool catalog
  --yes              skip installer prompts
  --no-shell         exit after setup without an inspection shell
  --name NAME        container name (default: unique dotfiles-debug name)
  -h, --help         show this help
EOF
}

while (($#)); do
  case "$1" in
  --profile | --with | --name)
    [[ -n "${2:-}" && "$2" != --* ]] || { usage >&2; exit 2; }
    case "$1" in
    --profile) PROFILE="$2" ;;
    --with) OPTIONAL_STEPS="$2" ;;
    --name) CONTAINER="$2" ;;
    esac
    shift
    ;;
  --yes) ASSUME_YES=true ;;
  --skip-managed-tools) SKIP_MANAGED_TOOLS=true ;;
  --no-shell) INSPECT_SHELL=false ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
  esac
  shift
done

case "$PROFILE" in
core | full) ;;
*) printf 'Unknown profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac
DOTFILES_DIR="$ROOT" DOTFILES_PROFILE="$PROFILE" DOTFILES_WITH="$OPTIONAL_STEPS" \
  DOTFILES_SKIP_MANAGED_TOOLS="$SKIP_MANAGED_TOOLS" \
  bash -c 'source "$1/setup/linux.sh"; validate_optional_steps' _ "$ROOT"

command -v docker > /dev/null 2>&1 || { printf 'Docker is required.\n' >&2; exit 1; }
docker info > /dev/null
image="$(docker build --quiet --file "$ROOT/scripts/debug-linux.Dockerfile" "$ROOT/scripts")"

terminal_args=()
if [[ -t 0 && -t 1 ]]; then
  terminal_args+=(--interactive --tty)
else
  ASSUME_YES=true
  INSPECT_SHELL=false
fi

printf 'Container: %s\n' "$CONTAINER"
printf 'Inspect:   docker start --attach --interactive %s\n' "$CONTAINER"
printf 'Logs:      docker logs %s\n' "$CONTAINER"
printf 'Remove:    docker rm %s\n\n' "$CONTAINER"

docker run --name "$CONTAINER" "${terminal_args[@]}" \
  --volume "$ROOT/home:/source/home:ro" \
  --volume "$ROOT/setup:/source/setup:ro" \
  --volume "$ROOT/.chezmoiroot:/source/.chezmoiroot:ro" \
  --env DOTFILES_PROFILE="$PROFILE" \
  --env DOTFILES_ASSUME_YES="$ASSUME_YES" \
  --env DOTFILES_WITH="$OPTIONAL_STEPS" \
  --env DOTFILES_SKIP_MANAGED_TOOLS="$SKIP_MANAGED_TOOLS" \
  --env DOTFILES_DEBUG_SHELL="$INSPECT_SHELL" \
  --env TERM="${TERM:-xterm-256color}" \
  --env COLORTERM="${COLORTERM:-}" \
  --env NO_COLOR="${NO_COLOR:-}" \
  "$image"
