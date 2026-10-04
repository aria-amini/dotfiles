#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.local/share/chezmoi}"
PROFILE=full
ASSUME_YES=false
DRY_RUN=false
EXISTING_SOURCE=false

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

usage() {
  cat << 'EOF'
Usage: run_bootstrap.sh [options]

Bootstrap chezmoi on macOS and Linux, then apply dotfiles and OS setup.

Options:
  --profile PROFILE  Linux setup: core or full (default: full)
  --yes              use defaults without prompts; defer authentication
  --dry-run          preview bootstrap and apply without an install
  --source DIR       apply an existing source directory
  -h, --help         show this help

Linux core installs base packages, bootstrap tools, Nix, and the login shell.
Linux full also installs managed tools, workspace tools, and optional services.

On Windows, run home/.chezmoiscripts/run_bootstrap.ps1 in PowerShell.
EOF
}

while (($#)); do
  case "$1" in
  --yes) ASSUME_YES=true ;;
  --dry-run) DRY_RUN=true ;;
  --profile)
    [[ -n "${2:-}" && "$2" != --* ]] || { usage >&2; exit 2; }
    PROFILE="$2"
    shift
    ;;
  --profile=*) PROFILE="${1#--profile=}" ;;
  --source)
    [[ -n "${2:-}" && "$2" != --* ]] || { usage >&2; exit 2; }
    DOTFILES_DIR="$2"
    EXISTING_SOURCE=true
    shift
    ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
  esac
  shift
done

case "$PROFILE" in
core | full) ;;
*) die "unknown profile: $PROFILE (expected core or full)" ;;
esac

os="$(uname -s)"
case "$os" in
Linux | Darwin) ;;
MINGW* | MSYS* | CYGWIN* | Windows*)
  die "run home/.chezmoiscripts/run_bootstrap.ps1 in PowerShell"
  ;;
*) die "unsupported OS: $os" ;;
esac

case "$DOTFILES_DIR" in
/*) ;;
*) DOTFILES_DIR="$PWD/$DOTFILES_DIR" ;;
esac
if [[ $EXISTING_SOURCE == true ]]; then
  [[ -d "$DOTFILES_DIR" ]] || die "source directory does not exist: $DOTFILES_DIR"
fi
if [[ -d "$DOTFILES_DIR" ]]; then
  DOTFILES_DIR="$(cd "$DOTFILES_DIR" && pwd -P)"
  if [[ $EXISTING_SOURCE == false && ! -e "$DOTFILES_DIR/.git" && ! -e "$DOTFILES_DIR/.jj" ]]; then
    die "source directory exists without a checkout; use --source $DOTFILES_DIR"
  fi
  EXISTING_SOURCE=true
elif [[ -e "$DOTFILES_DIR" ]]; then
  die "source path is not a directory: $DOTFILES_DIR"
fi

export PATH="$HOME/.local/bin:$PATH"
export DOTFILES_PROFILE="$PROFILE" DOTFILES_ASSUME_YES="$ASSUME_YES"

apply_args=(--source "$DOTFILES_DIR")
if [[ $ASSUME_YES == true || ! -t 0 || ! -t 1 ]]; then
  apply_args+=(--no-tty --error-on-conflict)
fi
if [[ $EXISTING_SOURCE == true ]]; then
  apply_args+=(apply)
else
  apply_args+=(init --apply --use-builtin-git=true aria-amini)
fi

if [[ $DRY_RUN == true ]]; then
  if ! command -v chezmoi > /dev/null 2>&1; then
    printf '[dry-run] Install chezmoi in %s/.local/bin\n' "$HOME"
  fi
  printf '[dry-run] chezmoi %s\n' "${apply_args[*]}"
  if [[ $os == Linux ]]; then
    printf '[dry-run] Linux setup profile: %s\n' "$PROFILE"
  fi
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

printf 'chezmoi %s\n' "${apply_args[*]}"
chezmoi "${apply_args[@]}"
