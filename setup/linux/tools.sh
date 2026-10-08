#!/usr/bin/env bash

managed_tool_names() {
  awk '
    /^\[tools\.("[^"]+"|[A-Za-z0-9_-]+)\][[:space:]]*(#.*)?$/ {
      name = $0
      sub(/^\[tools\./, "", name)
      sub(/\].*$/, "", name)
      gsub(/"/, "", name)
      if (!seen[name]++) print name
    }
    /^\[tools\]/ { tools = 1; next }
    /^\[/ { tools = 0 }
    tools && /^[[:space:]]*("[^"]+"|[A-Za-z0-9_-]+)[[:space:]]*=/ {
      sub(/[[:space:]]*=.*/, "")
      gsub(/["[:space:]]/, "")
      if (!seen[$0]++) print
    }
  ' "$DOTFILES_DIR/home/dot_config/mise/config.toml"
}

managed_tools_status() {
  local -a catalog=()
  mapfile -t catalog < <(managed_tool_names)
  local count=${#catalog[@]} tools name installed=0
  local -A available=()
  if ! command -v mise > /dev/null 2>&1; then
    printf '0/%s installed; install' "$count"
    return
  fi
  if ! tools="$(MISE_OFFLINE=true MISE_NO_ENV=true MISE_NO_HOOKS=true MISE_COLOR=false \
    timeout 5 mise ls --installed --no-header 2> /dev/null)"; then
    printf '?/%s installed; sync' "$count"
    return
  fi
  while read -r name _; do
    [[ -n $name ]] || continue
    available["$name"]=true
  done <<< "$tools"
  for name in "${catalog[@]}"; do
    [[ ${available[$name]:-false} == false ]] || installed=$((installed + 1))
  done
  if [[ $installed == "$count" ]]; then
    printf '%s/%s installed; sync' "$installed" "$count"
  else
    printf '%s/%s installed; install' "$installed" "$count"
  fi
}

git_at_least() {
  local have
  command -v git > /dev/null 2>&1 || return 1
  have="$(git --version 2> /dev/null | awk 'NR==1{print $3}')"
  [[ -n "$have" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$have" "$1" | sort -V | head -n1)" == "$1" ]]
}

# System

phase_apt() {
  need_sudo
  local attempt
  for attempt in 1 2 3; do
    if run 'Updating package index' --sudo apt-get update; then
      break
    fi
    [[ $attempt != 3 ]] || return 1
    warn "apt-get update failed; retrying ($attempt/3)"
    sleep 2
  done
  run 'Installing base packages' --sudo \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    software-properties-common xz-utils zsh curl ca-certificates libcap2-bin procps
  show_version Zsh 1 zsh --version
  if [[ $IS_WSL == true ]] && ! grep -qs 'appendWindowsPath=false' /etc/wsl.conf; then
    run_task 'Disabling Windows PATH interop' --sudo tee -a /etc/wsl.conf \
      <<< $'\n[interop]\nappendWindowsPath=false'
    NOTES+=("WSL interop: run 'wsl.exe --shutdown' on the Windows host to apply appendWindowsPath=false")
  fi
}

phase_git() {
  if ! git_at_least 2.41; then
    run 'Adding the Git repository' --sudo add-apt-repository -y ppa:git-core/ppa
    run 'Installing Git from ppa:git-core' --sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git
    git_at_least 2.41 || die 'git >= 2.41 required after ppa install'
  fi
  show_version Git 2 git --version
}

phase_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]]; then
    run 'Setting Zsh as the default shell' --sudo usermod -s "$zsh_path" "$USER"
    NOTES+=('Open a new login session to use Zsh.')
  fi
  ok 'Login shell' 'Zsh'
}

phase_mise() {
  if ! command -v mise > /dev/null 2>&1; then
    run_script 'Installing mise' https://mise.run sh
  fi
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  show_version Mise 0 mise --version
}

phase_github_notice() {
  if ! MISE_AUTO_INSTALL=false MISE_OFFLINE=true MISE_NO_ENV=true MISE_NO_HOOKS=true \
    timeout 5 gh --version > /dev/null 2>&1; then
    return 0
  fi
  if ! MISE_AUTO_INSTALL=false MISE_OFFLINE=true MISE_NO_ENV=true MISE_NO_HOOKS=true \
    timeout 5 gh auth status > /dev/null 2>&1; then
    NOTES+=('Optional GitHub sign-in: gh auth login --web')
  fi
}

# Dotfiles

phase_nix() {
  if ! command -v nix > /dev/null 2>&1; then
    run_script 'Installing Nix' https://nixos.org/nix/install sh --no-daemon
  fi
  if [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck source=/dev/null
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
  command -v nix > /dev/null 2>&1 || die 'nix not on PATH after install'
  show_version Nix 2 nix --version
  # Nix adds a marked PATH block. The managed zshrc already provides this PATH.
  local profile
  for profile in .zshrc .bashrc .bash_profile .profile; do
    if [[ -f "$HOME/$profile" ]]; then
      sed -i '/# added by Nix installer[[:space:]]*$/d' "$HOME/$profile"
    fi
  done
}

phase_mise_tools() {
  if [[ $SKIP_MANAGED_TOOLS == true ]]; then
    detail 'Managed tools skipped (debug)'
    return
  fi
  run 'Installing managed tools' --live mise install
  ok 'Managed tools' 'up to date'
}

phase_dotfiles() {
  # shellcheck disable=SC2016,SC2153
  run 'Applying dotfiles' env DOTFILES_PROFILE="$PROFILE" DOTFILES_SKIP_MANAGED_TOOLS="$SKIP_MANAGED_TOOLS" bash -Eeuo pipefail -c '
    DOTFILES_DIR="$1"
    source "$DOTFILES_DIR/setup/common.sh"
    apply_dotfiles
  ' _ "$DOTFILES_DIR" || return $?
  ok 'Dotfiles' 'applied'
}
