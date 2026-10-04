#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE="${DOTFILES_PROFILE:-full}"
ASSUME_YES="${DOTFILES_ASSUME_YES:-false}"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=setup/common.sh
source "$DOTFILES_DIR/setup/common.sh"
GUM_VERSION="0.16.2"
BOOTSTRAP_TOOLS=(github-cli@latest uv@latest github:herdrdev/herdr@0.9.1)
LOG_FILE="${TMPDIR:-/tmp}/dotfiles-setup-$(date +%Y%m%d-%H%M%S).log"
INTERACTIVE=false
IS_WSL=false
HAS_SYSTEMD=false
NOTES=()
CURRENT_PHASE=startup
SECTION_NO=0
SUMMARY_SHELL_CHANGED=false

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

on_err() {
  local rc=$?
  printf '✗ Failed during: %s (exit %s)\n' "$CURRENT_PHASE" "$rc" >&2
  printf '  command: %s\n  transcript: %s\n' "$BASH_COMMAND" "$LOG_FILE" >&2
}

ui() {
  if [[ $INTERACTIVE == true ]] && command -v gum > /dev/null 2>&1; then
    gum "$@"
    return
  fi
  printf '%s\n' "${*: -1}"
}

title() {
  ui style --border double --border-foreground 212 --padding '1 3' --margin '1 0' \
    --align center --width 44 'dotfiles — github.com/aria-amini/dotfiles'
}

phase_begin() {
  CURRENT_PHASE="$1"
}

section_begin() {
  SECTION_NO=$((SECTION_NO + 1))
  ui style --margin '1 0 0 0' --bold --foreground 99 "▸ [$SECTION_NO/${#SECTIONS[@]}] $1"
}

ok() {
  local line
  printf -v line '  ✓ %-22s %s' "$1" "${2:-}"
  ui style --foreground 82 "$line"
}

detail() {
  ui style --foreground 245 "    $1"
}

warn() {
  ui style --foreground 214 "  ! $1"
  NOTES+=("$1")
}

show_version() {
  local label="$1" field="$2" line=''
  shift 2
  command -v "$1" > /dev/null 2>&1 || return 0
  # Without || true, ERR fires in the subshell for optional version probes.
  IFS= read -r line < <("$@" 2>&1 || true) || true
  [[ -n "$line" ]] || return 0
  local -a fields
  read -r -a fields <<< "$line"
  ok "$label" "${fields[$field]:-}"
}

fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$@"
}

run_script() {
  local label="$1" url="$2" interpreter="$3"
  shift 3
  local script rc=0
  script="$(mktemp "${TMPDIR:-/tmp}/dotfiles-script-XXXXXX")"
  if fetch "$url" -o "$script"; then
    run "$label" "$interpreter" "$script" "$@" || rc=$?
  else
    rc=$?
    printf 'could not download script: %s\n' "$url" >&2
  fi
  rm -f -- "$script"
  return "$rc"
}

run() {
  local label="$1"
  shift
  if [[ $INTERACTIVE == false ]] || ! command -v gum > /dev/null 2>&1; then
    printf '  $ %s\n' "$*"
    "$@"
    return
  fi
  # gum spin does not capture child output. Preserve it for failures.
  local log rc
  log="$(mktemp "${TMPDIR:-/tmp}/dotfiles-run-XXXXXX")"
  # shellcheck disable=SC2016
  if gum spin --show-error --title "  $label..." -- \
    bash -c 'exec "$2" "${@:3}" >"$1" 2>&1' _ "$log" "$@"; then
    rm -f "$log"
  else
    rc=$?
    cat "$log" >&2
    rm -f "$log"
    return "$rc"
  fi
}

run_task() {
  local label="$1"
  run "$@" || return $?
  ok "$label"
}

run_plain() {
  "$@"
}

need_sudo() {
  [[ $EUID -eq 0 ]] && return 0
  command -v sudo > /dev/null 2>&1 || die "sudo not found; install sudo or run as root"
  if sudo -n true 2> /dev/null; then
    return
  fi
  [[ $INTERACTIVE == true ]] || die "sudo needs a password; run interactively or pre-cache credentials with 'sudo -v'"
  detail 'requesting administrator authentication'
  sudo -v
}

run_root() {
  local label="$1"
  shift
  need_sudo || return $?
  if [[ $EUID -eq 0 ]]; then
    run "$label" "$@"
  else
    run "$label" sudo "$@"
  fi
}

run_root_task() {
  local label="$1"
  run_root "$@" || return $?
  ok "$label"
}

root_plain() {
  need_sudo || return $?
  if [[ $EUID -eq 0 ]]; then
    run_plain "$@"
  else
    run_plain sudo "$@"
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

phase_gum() {
  phase_begin gum
  export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:$PATH"
  if ! command -v gum > /dev/null 2>&1; then
    local gum_arch
    case "$(uname -m)" in
    x86_64) gum_arch=x86_64 ;;
    aarch64) gum_arch=arm64 ;;
    *) die "unsupported arch: $(uname -m)" ;;
    esac
    (
        gum_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-gum-XXXXXX")"
        trap 'rm -rf -- "$gum_tmp"' EXIT
        mkdir -p "$HOME/.local/bin"
        fetch "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_${gum_arch}.tar.gz" \
          -o "$gum_tmp/gum.tar.gz"
        tar -xzf "$gum_tmp/gum.tar.gz" -C "$gum_tmp" "gum_${GUM_VERSION}_Linux_${gum_arch}/gum"
        mv "$gum_tmp/gum_${GUM_VERSION}_Linux_${gum_arch}/gum" "$HOME/.local/bin/gum"
    )
  fi
  title
  show_version Gum 2 "$HOME/.local/bin/gum" --version
}

phase_apt() {
  phase_begin apt
  need_sudo
  local attempt
  for attempt in 1 2 3; do
    if run_root 'Updating package index' apt-get update; then
      break
    fi
    [[ $attempt != 3 ]] || return 1
    warn "apt-get update failed; retrying ($attempt/3)"
    sleep 2
  done
  run_root_task 'Installing base packages' \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    software-properties-common xz-utils zsh curl ca-certificates
  show_version Zsh 1 zsh --version
  if [[ $IS_WSL == true ]] && ! grep -qs 'appendWindowsPath=false' /etc/wsl.conf; then
    run_root_task 'Disabling Windows PATH interop' tee -a /etc/wsl.conf \
      <<< $'\n[interop]\nappendWindowsPath=false'
    NOTES+=("WSL interop: run 'wsl.exe --shutdown' on the Windows host to apply appendWindowsPath=false")
  fi
}

phase_git() {
  phase_begin git
  if ! git_at_least 2.41; then
    run_root_task 'Adding the Git repository' add-apt-repository -y ppa:git-core/ppa
    run_root_task 'Installing Git from ppa:git-core' env DEBIAN_FRONTEND=noninteractive apt-get install -y git
    git_at_least 2.41 || die 'git >= 2.41 required after ppa install'
  fi
  show_version Git 2 git --version
}

phase_shell() {
  phase_begin shell
  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$zsh_path" ]]; then
    ok 'Zsh is the default shell'
  else
    run_root_task 'Setting Zsh as the default shell' usermod -s "$zsh_path" "$USER"
    SUMMARY_SHELL_CHANGED=true
  fi
}

# Developer tools

phase_mise() {
  phase_begin mise
  if ! command -v mise > /dev/null 2>&1; then
    run_script 'Installing mise' https://mise.run sh
    ok 'Installing mise'
  fi
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  # Explicit versions also work when an existing config has no tool defaults.
  run_task 'Installing bootstrap tools (gh, uv, herdr)' mise install --quiet "${BOOTSTRAP_TOOLS[@]}"
  show_version Mise 0 mise --version
}

phase_gh() {
  phase_begin gh
  show_version 'GitHub CLI' 2 mise exec --quiet "${BOOTSTRAP_TOOLS[@]}" -- gh --version
  if mise exec --quiet "${BOOTSTRAP_TOOLS[@]}" -- gh auth status > /dev/null 2>&1; then
    ok 'GitHub authenticated'
  elif [[ $INTERACTIVE == true ]] && gum confirm 'Sign in to GitHub now?' < /dev/tty; then
    run_plain mise exec --quiet "${BOOTSTRAP_TOOLS[@]}" -- gh auth login --web --git-protocol https < /dev/tty
    ok 'GitHub authenticated'
  else
    warn "gh not authenticated; run 'gh auth login --web' anytime for GitHub auth (optional)"
  fi
}

phase_nix() {
  phase_begin nix
  if ! command -v nix > /dev/null 2>&1; then
    run_script 'Installing Nix' https://nixos.org/nix/install sh --no-daemon
    ok 'Installing Nix'
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
  phase_begin mise_tools
  run_task 'Installing managed tools' mise install --quiet
}

phase_dotfiles() {
  phase_begin dotfiles
  apply_dotfiles
  ok 'Applying dotfiles'
}

phase_workspaces() {
  phase_begin workspaces
  local repo="$HOME/tools/herdr-jj-workspaces" dep
  for dep in git uv herdr; do
    command -v "$dep" > /dev/null 2>&1 || die "workspace setup requires $dep"
  done
  if [[ ! -d "$repo/.git" ]]; then
    run_task 'Cloning workspace tools' git clone https://github.com/aria-amini/tools "$repo"
  fi
  if ! command -v herdr-jj > /dev/null 2>&1; then
    run_task 'Installing workspace tools' uv tool install --python 3.14 --editable "$repo/herdr-jj-workspaces"
  fi
  if ! herdr plugin list 2> /dev/null | grep -q aamini.jj; then
    run_task 'Linking the jj workspace plugin' herdr plugin link "$repo/herdr-jj-workspaces/herdr-plugin"
  fi
}

# Services

phase_docker() {
  phase_begin docker
  if ! command -v docker > /dev/null 2>&1; then
    run_root_task 'Creating the Docker key directory' install -m 0755 -d /etc/apt/keyrings
    run_root_task 'Downloading the Docker key' curl -fsSL --retry 3 \
      https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    run_root_task 'Setting Docker key permissions' chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck source=/dev/null
    . /etc/os-release
    run_root_task 'Adding the Docker repository' tee /etc/apt/sources.list.d/docker.list \
      <<< "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable"
    run_root_task 'Updating the Docker package index' apt-get update
    run_root_task 'Installing Docker' env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  show_version Docker 2 docker --version
  if ! id -nG "$USER" | grep -qw docker; then
    run_root_task 'Adding user to docker group' usermod -aG docker "$USER"
    NOTES+=('Docker group: log out and back in to run docker without sudo')
  fi
  if [[ $HAS_SYSTEMD == true ]]; then
    run_root_task 'Enabling Docker' systemctl enable --now docker
  else
    detail 'no systemd; start dockerd manually with: sudo dockerd'
  fi
}

phase_tailscale() {
  phase_begin tailscale
  if [[ $HAS_SYSTEMD == false ]]; then
    detail 'no systemd; skipping Tailscale service setup'
    return
  fi
  need_sudo
  if ! dpkg -s tailscale > /dev/null 2>&1; then
    run_script 'Installing Tailscale' https://tailscale.com/install.sh sh
    ok 'Installing Tailscale'
  fi
  run_root_task 'Enabling tailscaled' systemctl enable --now tailscaled
  if root_plain tailscale status > /dev/null 2>&1; then
    ok 'Tailscale authenticated'
  elif [[ $INTERACTIVE == true ]]; then
    warn 'Tailscale authentication required; open the login link printed next'
    if ! root_plain timeout 180 tailscale up; then
      warn "tailscale auth not completed; run 'sudo tailscale up' after install"
      return
    fi
  else
    warn "tailscale not authenticated; run 'sudo tailscale up' after install"
    return
  fi
  run_root_task 'Enabling Tailscale SSH' tailscale set --ssh=true || warn 'Tailscale SSH not enabled; check tailnet ACLs'
  run_root_task 'Setting Tailscale operator' tailscale set --operator="$USER" || warn 'Tailscale operator not set'
}

phase_pitchfork() {
  phase_begin pitchfork
  if [[ $HAS_SYSTEMD == false ]]; then
    detail 'no systemd; skipping Pitchfork URL setup'
    return
  fi
  local pitchfork_host="${PITCHFORK_PROXY_HOST:-}" pitchfork_access=''
  if [[ -z "$pitchfork_host" && $INTERACTIVE == true ]]; then
    pitchfork_access="$(gum choose --header 'Where will you open local app URLs?' \
      'On this machine' 'From another machine' < /dev/tty)"
    if [[ "$pitchfork_access" == 'From another machine' ]]; then
      pitchfork_host=0.0.0.0
    else
      pitchfork_host=127.0.0.1
    fi
  fi
  if [[ -z "$pitchfork_host" ]] && root_plain tailscale status > /dev/null 2>&1; then
    pitchfork_host=0.0.0.0
  fi
  pitchfork_host="${pitchfork_host:-127.0.0.1}"
  detail 'Pitchfork installs a boot service and a local TLS certificate authority'
  run_task 'Configuring Pitchfork URLs' mise -C "$DOTFILES_DIR" run setup-pitchfork "$pitchfork_host"
}

write_t3_settings() {
  # Home and binary paths can contain shell quotes.
  # shellcheck disable=SC2016
  run_task 'Writing T3 Code settings' bash -Eeuo pipefail -c '
    mkdir -p "${2%/*}"
    settings_tmp="$(mktemp "$2.XXXXXX")"
    trap "rm -f -- \"\$settings_tmp\"" EXIT
    jq -n --arg b "$1" "{providers: {opencode: {enabled: true, binaryPath: \$b}}}" > "$settings_tmp"
    mv -- "$settings_tmp" "$2"
  ' _ "$1" "$2"
}

phase_t3() {
  phase_begin t3
  if [[ $HAS_SYSTEMD == false ]]; then
    detail 'no systemd; skipping T3 Code'
    return
  fi
  detail 'T3 Code installs a systemd user service for pairing remote devices'
  if [[ $INTERACTIVE == false ]] || ! gum confirm 'Install T3 Code?' < /dev/tty; then
    warn 'T3 Code not installed; re-run setup interactively to add it'
    return
  fi
  local opencode_bin t3_settings node_bin_dir
  opencode_bin="$(mise -C "$DOTFILES_DIR" which opencode)"
  t3_settings="$HOME/.t3/userdata/settings.json"
  if [[ ! -f "$t3_settings" ]]; then
    write_t3_settings "$opencode_bin" "$t3_settings"
  fi
  node_bin_dir="$(dirname "$(mise -C "$DOTFILES_DIR" which node)")"
  if [[ ! -x /usr/bin/g++ ]]; then
    run_root_task 'Installing build tools' env DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
  fi
  if [[ -f "$HOME/.config/systemd/user/t3code.service" ]]; then
    run_task 'Updating T3 Code' env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ \
      NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" "$node_bin_dir/npx" --yes t3@0.0.40 service update
  else
    run_task 'Installing T3 Code' env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ \
      NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" "$node_bin_dir/npx" --yes t3@0.0.40 service install
    NOTES+=($'Pair a device:\n  t3 pair --tailscale --tailscale-serve-port 8443\n  then scan the QR code')
  fi
}

# Main

main() {
  [[ "$(uname -s)" == Linux ]] || die 'this setup supports Linux only'
  case "$PROFILE" in
  core | full) ;;
  *) die "unknown profile: $PROFILE (expected core or full)" ;;
  esac
  case "$(uname -m)" in
  x86_64 | aarch64) ;;
  *) die "unsupported arch: $(uname -m)" ;;
  esac
  command -v curl > /dev/null 2>&1 || die 'curl is required'
  cd "$HOME"
  if [[ -t 1 && $ASSUME_YES == false ]]; then
    INTERACTIVE=true
  fi
  if grep -qi microsoft /proc/version 2> /dev/null; then
    IS_WSL=true
  fi
  if [[ -d /run/systemd/system ]]; then
    HAS_SYSTEMD=true
  fi
  SECTIONS=('System|apt git' 'Developer Tools|mise gh nix dotfiles')
  if [[ $PROFILE == full ]]; then
    SECTIONS+=(
      'Managed Tools|mise_tools workspaces'
      'Docker|docker'
      'Connectivity|tailscale pitchfork'
      'Applications|t3'
    )
  fi
  SECTIONS+=('Finish|shell')
  trap on_err ERR
  exec > >(tee "$LOG_FILE") 2>&1
  printf 'transcript: %s\n' "$LOG_FILE"
  phase_gum
  local entry phase
  local -a section_phases
  for entry in "${SECTIONS[@]}"; do
    section_begin "${entry%%|*}"
    read -r -a section_phases <<< "${entry#*|}"
    for phase in "${section_phases[@]}"; do
      "phase_$phase"
    done
  done
  ui style --border rounded --border-foreground 82 --padding '0 3' --margin '1 0' '✓ Setup complete'
  local note
  for note in "${NOTES[@]+"${NOTES[@]}"}"; do
    ui style --foreground 214 "$note"
  done
  if [[ $SUMMARY_SHELL_CHANGED == true && $INTERACTIVE == true && $IS_WSL == false ]]; then
    if gum confirm 'Reboot now to apply zsh as the login shell?' < /dev/tty; then
      root_plain reboot
    fi
  fi
}

main
