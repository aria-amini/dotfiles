#!/usr/bin/env bash
set -euo pipefail
cd "$HOME"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.local/share/chezmoi}"

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "this installer supports macOS only"
command -v curl > /dev/null 2>&1 || die "curl is required: xcode-select --install provides curl"

export PATH="$HOME/.local/bin:$PATH"

if ! command -v chezmoi > /dev/null 2>&1; then
  printf 'installing chezmoi\n'
  curl -fsSL --retry 3 https://get.chezmoi.io | sh -s -- -b "$HOME/.local/bin"
fi

# init uses chezmoi's embedded git client, so this works before the Xcode
# CLT provides a system git. The apply runs run_once_install-darwin, which
# installs the CLT, mise, gh, nix, and the mise toolset.
init_args=(init --apply)
if [[ "$DOTFILES_DIR" != "$HOME/.local/share/chezmoi" ]]; then
  init_args+=(--source "$DOTFILES_DIR")
fi

exec chezmoi "${init_args[@]}" aria-amini
