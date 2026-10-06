#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_DIR="$HOME/.local/share/chezmoi"
mkdir -p "$DOTFILES_DIR"
cp -R /source/home /source/setup /source/.chezmoiroot "$DOTFILES_DIR/"

if ! command -v chezmoi > /dev/null 2>&1; then
  installer="$(mktemp)"
  trap 'rm -f -- "$installer"' EXIT
  curl -fsSL --retry 3 --connect-timeout 10 https://get.chezmoi.io -o "$installer"
  sh "$installer" -b "$HOME/.local/bin"
  rm -f -- "$installer"
  trap - EXIT
fi

status=0
bash "$DOTFILES_DIR/setup/linux.sh" || status=$?
printf '\nInstaller exit code: %s\n' "$status"

if [[ ${DOTFILES_DEBUG_SHELL:-false} == true && -t 0 && -t 1 ]]; then
  printf 'Inspect the container. Run bash %q to repeat setup.\n' "$DOTFILES_DIR/setup/linux.sh"
  printf 'Exit this shell to stop the container.\n\n'
  bash --noprofile --norc -i || true
fi

exit "$status"
