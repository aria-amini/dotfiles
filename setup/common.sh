#!/usr/bin/env bash

fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$@"
}

apply_dotfiles() {
  local -a args=(--source "$DOTFILES_DIR")
  if [[ ${DOTFILES_ASSUME_YES:-false} == true || ! -t 0 || ! -t 1 ]]; then
    args+=(--no-tty --error-on-conflict)
  fi
  args+=(apply)
  printf 'chezmoi %s\n' "${args[*]}"
  chezmoi "${args[@]}"
}
