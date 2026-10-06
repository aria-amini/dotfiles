#!/usr/bin/env bash
set -euo pipefail

PROFILE=full
ASSUME_YES=false
DRY_RUN=false
OPTIONAL_STEPS=''
BRANCH=''
SOURCE_DIR=''
SKIP_MANAGED_TOOLS=false

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

usage() {
  cat << 'EOF'
Usage: bootstrap.sh [options]

Obtain the dotfiles source, then run macOS or Linux machine setup.

Options:
  --profile PROFILE  Linux setup: core or full (default: full)
  --with STEPS       Linux optional steps: docker,tailscale,pitchfork,t3
  --skip-managed-tools  Linux debug: skip the managed mise tool catalog
  --branch BRANCH    branch to clone into a new source directory
  --source DIR       use a specific chezmoi repository directory
  --yes              use defaults without prompts; defer authentication
  --dry-run          preview bootstrap and setup without an install
  -h, --help         show this help

Linux core installs base packages, bootstrap tools, Nix, and the login shell.
Linux full also installs managed tools and workspace tools.
Select optional services interactively or with --with (comma-separated).

On Windows, run bootstrap.ps1 in PowerShell.
EOF
}

while (($#)); do
  case "$1" in
  --yes) ASSUME_YES=true ;;
  --dry-run) DRY_RUN=true ;;
  --skip-managed-tools) SKIP_MANAGED_TOOLS=true ;;
  --profile)
    [[ -n "${2:-}" && "$2" != --* ]] || { usage >&2; exit 2; }
    PROFILE="$2"
    shift
    ;;
  --profile=*) PROFILE="${1#--profile=}" ;;
  --with)
    [[ -n "${2:-}" && "$2" != --* ]] || { usage >&2; exit 2; }
    OPTIONAL_STEPS="$2"
    shift
    ;;
  --with=*) OPTIONAL_STEPS="${1#--with=}" ;;
  --branch | --source)
    [[ -n "${2:-}" && "$2" != --* ]] || { usage >&2; exit 2; }
    if [[ $1 == --branch ]]; then BRANCH="$2"; else SOURCE_DIR="$2"; fi
    shift
    ;;
  --branch=*) BRANCH="${1#--branch=}" ;;
  --source=*) SOURCE_DIR="${1#--source=}" ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
  esac
  shift
done

case "$PROFILE" in
core | full) ;;
*) die "unknown profile: $PROFILE (expected core or full)" ;;
esac

IFS=, read -r -a optional_steps <<< "$OPTIONAL_STEPS"
for step in "${optional_steps[@]}"; do
  case "$step" in
  docker | tailscale | pitchfork | t3) ;;
  *) die "unknown optional step: $step (expected docker, tailscale, pitchfork, t3)" ;;
  esac
done
[[ $PROFILE == full || -z $OPTIONAL_STEPS ]] || die '--with requires the full profile'

os="$(uname -s)"
case "$os" in
Linux) setup_script=linux.sh ;;
Darwin) setup_script=darwin.sh ;;
MINGW* | MSYS* | CYGWIN* | Windows*)
  die "run bootstrap.ps1 in PowerShell"
  ;;
*) die "unsupported OS: $os" ;;
esac
[[ $os == Linux || -z $OPTIONAL_STEPS ]] || die '--with supports Linux only'
[[ $os == Linux || $SKIP_MANAGED_TOOLS == false ]] || die '--skip-managed-tools supports Linux only'

export PATH="$HOME/.local/bin:$PATH"
export DOTFILES_PROFILE="$PROFILE" DOTFILES_ASSUME_YES="$ASSUME_YES" DOTFILES_WITH="$OPTIONAL_STEPS"
export DOTFILES_SKIP_MANAGED_TOOLS="$SKIP_MANAGED_TOOLS"

if [[ $DRY_RUN == true ]]; then
  if ! command -v chezmoi > /dev/null 2>&1; then
    printf '[dry-run] Install chezmoi in %s/.local/bin\n' "$HOME"
  fi
  printf '[dry-run] Initialize dotfiles with chezmoi\n'
  [[ -z $BRANCH ]] || printf '[dry-run] Initial repository branch: %s\n' "$BRANCH"
  [[ -z $SOURCE_DIR ]] || printf '[dry-run] Repository directory: %s\n' "$SOURCE_DIR"
  printf '[dry-run] Run setup/%s from the chezmoi source directory\n' "$setup_script"
  printf '[dry-run] Apply dotfiles\n'
  [[ $os != Linux ]] || printf '[dry-run] Linux setup profile: %s\n' "$PROFILE"
  [[ $os != Linux ]] || printf '[dry-run] Optional steps: %s\n' "${OPTIONAL_STEPS:-none}"
  [[ $os != Linux ]] || printf '[dry-run] Skip managed tools: %s\n' "$SKIP_MANAGED_TOOLS"
  exit 0
fi

if ! command -v chezmoi > /dev/null 2>&1; then
  command -v curl > /dev/null 2>&1 || die "curl is required"
  download_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap-XXXXXX")"
  trap 'rm -rf -- "$download_dir"' EXIT
  curl -fsSL --retry 3 --connect-timeout 10 https://get.chezmoi.io \
    -o "$download_dir/chezmoi.sh" || die "could not download chezmoi installer"
  sh "$download_dir/chezmoi.sh" -b "$HOME/.local/bin"
fi

chezmoi_args=()
[[ -z $SOURCE_DIR ]] || chezmoi_args+=(--source "$SOURCE_DIR")
init_args=(--use-builtin-git=true)
[[ -z $BRANCH ]] || init_args+=(--branch "$BRANCH")
chezmoi "${chezmoi_args[@]}" init "${init_args[@]}" aria-amini
DOTFILES_DIR="$(chezmoi "${chezmoi_args[@]}" execute-template '{{ .chezmoi.workingTree }}')"
export DOTFILES_DIR
[[ -f "$DOTFILES_DIR/setup/$setup_script" ]] || die "setup/$setup_script is missing from $DOTFILES_DIR; use --source DIR --branch BRANCH for a fresh clone of the setup branch"
bash "$DOTFILES_DIR/setup/$setup_script"
