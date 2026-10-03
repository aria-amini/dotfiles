#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/aria-amini/dotfiles/main"

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

usage() {
  cat << 'EOF'
Usage: install.sh [options]

Bootstraps dotfiles on macOS and Linux. The wrapper detects the OS and
runs install-mac.sh or install-linux.sh. Options pass through to the
OS installer. On Windows, run install-windows.ps1 in PowerShell:

  irm https://raw.githubusercontent.com/aria-amini/dotfiles/main/install-windows.ps1 | iex
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
esac

os="$(uname -s)"
case "$os" in
Linux) script=install-linux.sh ;;
Darwin) script=install-mac.sh ;;
MINGW* | MSYS* | CYGWIN* | Windows*)
  die "run install-windows.ps1 in PowerShell:
  irm $REPO_RAW/install-windows.ps1 | iex"
  ;;
*) die "unsupported OS: $os" ;;
esac

# Prefer the sibling installer when the wrapper runs from a checkout.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2> /dev/null && pwd)" || here=""
if [[ -n "$here" && -f "$here/$script" ]]; then
  exec bash "$here/$script" "$@"
fi

command -v curl > /dev/null 2>&1 || die "curl is required"
exec bash <(curl -fsSL --retry 3 "$REPO_RAW/$script") "$@"
