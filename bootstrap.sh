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
Usage: bootstrap.sh [options]

Obtain the dotfiles source, then run macOS or Linux machine setup.

Options:
  --profile PROFILE  Linux setup: core or full (default: full)
  --yes              use defaults without prompts; defer authentication
  --dry-run          preview bootstrap and setup without an install
  --source DIR       apply an existing source directory
  -h, --help         show this help

Linux core installs base packages, bootstrap tools, Nix, and the login shell.
Linux full also installs managed tools, workspace tools, and optional services.

On Windows, run bootstrap.ps1 in PowerShell.
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
Linux) setup_script=linux.sh ;;
Darwin) setup_script=darwin.sh ;;
MINGW* | MSYS* | CYGWIN* | Windows*)
  die "run bootstrap.ps1 in PowerShell"
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
export DOTFILES_DIR DOTFILES_PROFILE="$PROFILE" DOTFILES_ASSUME_YES="$ASSUME_YES"

if [[ $DRY_RUN == true ]]; then
  if ! command -v chezmoi > /dev/null 2>&1; then
    printf '[dry-run] Install chezmoi in %s/.local/bin\n' "$HOME"
  fi
  if [[ $EXISTING_SOURCE == false ]]; then
    printf '[dry-run] Initialize dotfiles source in %s with embedded Git\n' "$DOTFILES_DIR"
  fi
  printf '[dry-run] Run %s/setup/%s\n' "$DOTFILES_DIR" "$setup_script"
  printf '[dry-run] Apply dotfiles from %s\n' "$DOTFILES_DIR"
  [[ $os != Linux ]] || printf '[dry-run] Linux setup profile: %s\n' "$PROFILE"
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

if [[ $EXISTING_SOURCE == false ]]; then
  chezmoi --source "$DOTFILES_DIR" init --use-builtin-git=true aria-amini
fi
[[ -f "$DOTFILES_DIR/setup/$setup_script" ]] || die "setup script does not exist: $DOTFILES_DIR/setup/$setup_script"
bash "$DOTFILES_DIR/setup/$setup_script"
