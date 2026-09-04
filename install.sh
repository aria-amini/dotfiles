#!/usr/bin/env bash
set -euo pipefail
cd "$HOME"

# bootstrap: gum
GUM_VERSION="0.16.2"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v gum &> /dev/null; then
  mkdir -p "$HOME/.local/bin"
  arch="$(uname -m)"
  case "$arch" in
    x86_64) gum_arch="x86_64" ;;
    aarch64) gum_arch="arm64" ;;
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
  esac
  curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_${gum_arch}.tar.gz" \
    | tar -xz -C /tmp "gum_${GUM_VERSION}_Linux_${gum_arch}/gum"
  mv "/tmp/gum_${GUM_VERSION}_Linux_${gum_arch}/gum" "$HOME/.local/bin/gum"
fi

gum style \
  --border double --border-foreground 212 --padding "1 3" --margin "1 0" \
  --align center --width 44 \
  "$(gum style --bold --foreground 212 'dotfiles')" \
  "github.com/aria-amini/dotfiles"

section_total=6
section_current=0
current_section="bootstrap"
verbose=false
if [[ "${1:-}" == "--verbose" ]]; then
  verbose=true
  shift
fi
if (( $# )); then
  gum style --foreground 196 "Usage: $0 [--verbose]" >&2
  exit 2
fi
trap 'gum style --foreground 196 --bold "✗ Failed during: $current_section (exit $?)" >&2' ERR
section() {
  section_current=$((section_current + 1))
  current_section="$1"
  gum style --margin "1 0 0 0" --bold --foreground 99 "▸ [$section_current/$section_total] $1"
}
task() {
  gum style --bold --foreground 245 "  $1"
}
complete_task() {
  local status
  if [[ -n "${2:-}" ]]; then
    printf -v status '  ✓ %-22s %s' "$1" "$2"
  else
    status="  ✓ $1"
  fi
  gum style --foreground 82 "$status"
}
task_detail() {
  local detail
  printf -v detail '    %-22s %s' "" "$1"
  gum style --foreground 245 "$detail"
}
run_command() {
  local title="$1"
  shift

  if [[ "$verbose" == true ]]; then
    task "$title"
    "$@"
  else
    gum spin --show-error --title "  $title..." -- "$@"
  fi
}
run_task() {
  local title="$1"
  shift
  run_command "$title" "$@"
  complete_task "$title"
}
show_command_version() {
  local label="$1"
  local field="$2"
  local line
  local -a fields
  shift 2
  IFS= read -r line < <("$@" 2>&1)
  read -r -a fields <<< "$line"
  complete_task "$label" "${fields[$field]}"
}
ensure_sudo() {
  if sudo -n true 2> /dev/null; then
    return
  fi
  task "Administrator authentication"
  sudo -v
}

# System
section "System"
ensure_sudo
run_task "Updating package index" sudo apt-get update
run_command "Installing system packages" sudo DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common xz-utils zsh
show_command_version "APT" 1 apt-get --version
show_command_version "Zsh" 1 zsh --version
show_command_version "XZ" 3 xz --version

# git (latest stable from ppa, jj requires >= 2.41)
if command -v git &> /dev/null && grep -qs "git-core" /etc/apt/sources.list.d/*; then
  show_command_version "Git" 2 git --version
else
  run_command "Installing Git" bash -c '
    sudo add-apt-repository -y ppa:git-core/ppa
    sudo DEBIAN_FRONTEND=noninteractive apt install git -y
  '
  show_command_version "Git" 2 git --version
fi

if [ ! -d "$HOME/dotfiles" ]; then
  run_command "Cloning dotfiles" git clone "https://github.com/aria-amini/dotfiles.git" "$HOME/dotfiles"
fi
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if ! command -v chezmoi &> /dev/null; then
  run_command "Installing chezmoi" sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi
show_command_version "Chezmoi" 2 chezmoi --version
task "Applying dotfiles"
chezmoi init --source "$HOME/dotfiles" --apply
complete_task "Applying dotfiles"

if ! command -v nix &> /dev/null; then
  run_command "Installing Nix" bash -c "sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --no-daemon"
  # shellcheck source=/dev/null
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
show_command_version "Nix" 2 nix --version
# Nix adds this marked line to shell profiles. The script sources Nix itself,
# and the managed zshrc already adds the Nix profile bin directory to PATH.
for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$profile" ] || continue
  sed -i '/# added by Nix installer[[:space:]]*$/d' "$profile"
done

if command -v mise &> /dev/null; then
  :
else
  run_command "Installing mise" bash -c 'curl -fsSL https://mise.run | sh'
fi
eval "$(mise activate bash)"
show_command_version "Mise" 0 mise --version

if ! mise where github-cli &> /dev/null; then
  run_command "Installing GitHub CLI" mise install --quiet github-cli
fi
show_command_version "GitHub CLI" 2 gh --version
if gh auth status &> /dev/null; then
  task_detail "$(gh api user --jq .login)"
elif [ -t 0 ]; then
  task "GitHub authentication"
  gh auth login --web --git-protocol https
  task_detail "$(gh api user --jq .login)"
else
  gum style --foreground 214 "  authentication deferred: run gh auth login --web"
fi
mise --quiet trust -y "$HOME/dotfiles/mise.toml"
run_task "Linking Vite+ plugin" mise plugin link --force vite-plus "$HOME/dotfiles/tools/mise-vite-plus"

# Developer Tools
section "Developer Tools"
run_task "Installing managed tools" mise install --quiet
run_task "Installing repository tools" mise -C "$HOME/dotfiles" install --quiet --monorepo
run_task "Configuring repository tools" mise -C "$HOME/dotfiles" --quiet //:install
if [ -f "$HOME/ms-scripts/packages/ms-scripts/pyproject.toml" ]; then
  run_task "Installing Microsoft scripts" uv tool install \
    --python 3.14 \
    --editable \
    --reinstall \
    "$HOME/ms-scripts/packages/ms-scripts"
fi

# Docker
section "Docker"
docker_group_changed=false
if command -v docker &> /dev/null; then
  show_command_version "Docker" 2 docker --version
else
  run_command "Installing Docker" bash -c '
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  '
  show_command_version "Docker" 2 docker --version
fi
if id -nG "$USER" | grep -qw docker; then
  complete_task "Docker group"
else
  run_task "Adding user to docker group" sudo usermod -aG docker "$USER"
  docker_group_changed=true
fi
if [ -d /run/systemd/system ]; then
  run_task "Enabling Docker" sudo systemctl enable --now docker
else
  gum style --foreground 245 "  no systemd, start dockerd manually (use: sudo dockerd)"
fi

# Connectivity
section "Connectivity"
if [ -d /run/systemd/system ]; then
  if ! dpkg -s tailscale &> /dev/null; then
    run_task "Installing Tailscale" bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'
  else
    complete_task "Tailscale"
  fi
  run_task "Enabling Tailscale" sudo systemctl enable --now tailscaled
else
  gum style --foreground 245 "  no systemd, skipping (use: mise -C ~/dotfiles run tailscaled)"
fi

if [ -d /run/systemd/system ]; then
  if ! sudo tailscale status &> /dev/null; then
    gum style \
      --border rounded --border-foreground 214 --padding "0 3" --margin "1 0" \
      "$(gum style --bold --foreground 214 'Tailscale authentication required:')" \
      "open the login link from the command below"
    sudo tailscale up
  else
    complete_task "Tailscale authenticated"
  fi
  if sudo tailscale status &> /dev/null; then
    run_task "Configuring Tailscale operator" sudo tailscale set --operator="$USER"
  fi
else
  gum style --foreground 245 "  no systemd, skipping"
fi

if [ -d /run/systemd/system ]; then
  pitchfork_host="${PITCHFORK_PROXY_HOST:-}"
  if [[ -z "$pitchfork_host" && -t 0 ]]; then
    pitchfork_access="$(gum choose \
      --header "Where will you open local app URLs?" \
      "On this machine" \
      "From another machine")"
    if [[ "$pitchfork_access" == "From another machine" ]]; then
      pitchfork_host="0.0.0.0"
    else
      pitchfork_host="127.0.0.1"
    fi
  fi
  if [[ -z "$pitchfork_host" ]] && sudo tailscale status &> /dev/null; then
    pitchfork_host="0.0.0.0"
  fi
  pitchfork_host="${pitchfork_host:-127.0.0.1}"
  gum style --foreground 245 \
    "  Pitchfork installs a boot service and a local TLS certificate authority."
  run_task "Configuring Pitchfork URLs" mise run setup-pitchfork "$pitchfork_host"
else
  gum style --foreground 245 "  no systemd, skipping Pitchfork URL setup"
fi

# Applications
section "Applications"
if [ ! -d /run/systemd/system ]; then
  gum style --foreground 245 "  no systemd, skipping"
else
  opencode_bin="$(mise -C "$HOME/dotfiles" which opencode)"
  t3_settings="$HOME/.t3/userdata/settings.json"
  if [ ! -f "$t3_settings" ]; then
    mkdir -p "$(dirname "$t3_settings")"
    jq -n --arg binary_path "$opencode_bin" \
      '{providers: {opencode: {enabled: true, binaryPath: $binary_path}}}' \
      > "$t3_settings"
  fi
  node_bin_dir="$(dirname "$(mise -C "$HOME/dotfiles" which node)")"
  if [ ! -x /usr/bin/g++ ]; then
    run_task "Installing build tools" sudo DEBIAN_FRONTEND=noninteractive apt install -y build-essential
  fi
  if [ -f "$HOME/.config/systemd/user/t3code.service" ]; then
    run_task "Updating T3 Code" \
      env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" \
      "$node_bin_dir/npx" --yes t3@0.0.40 service update
  else
    run_task "Installing T3 Code" \
      env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" \
      "$node_bin_dir/npx" --yes t3@0.0.40 service install
  fi
fi

# Finish
section "Finish"
zsh_path="$(command -v zsh)"
shell_changed=false
if [ "$(getent passwd "$USER" | cut -d: -f7)" = "$zsh_path" ]; then
  complete_task "Zsh is the default shell"
else
  run_task "Setting Zsh as the default shell" sudo usermod -s "$zsh_path" "$USER"
  shell_changed=true
fi

gum style \
  --border rounded --border-foreground 82 --padding "0 3" --margin "1 0" \
  --foreground 82 "✓ Install complete"

if command -v tailscale &> /dev/null && ! sudo tailscale status &> /dev/null; then
  gum style \
    --border rounded --border-foreground 214 --padding "0 3" --margin "1 0" \
    "$(gum style --bold --foreground 214 'One manual step:')" \
    "run: sudo tailscale up" \
    "then open the login link it prints"
fi
if [ "$docker_group_changed" = true ]; then
  gum style \
    --border rounded --border-foreground 214 --padding "0 3" --margin "1 0" \
    "$(gum style --bold --foreground 214 'Docker group:')" \
    "log out and back in to run docker without sudo"
fi
if [ -f "$HOME/.config/systemd/user/t3code.service" ]; then
  gum style \
    --border rounded --border-foreground 214 --padding "0 3" --margin "1 0" \
    "$(gum style --bold --foreground 214 'Pair a device:')" \
    "run: t3 pair --tailscale --tailscale-serve-port 8443" \
    "then scan the QR code from your phone"
fi

if [ "$shell_changed" = true ]; then
  gum confirm "Reboot now to apply zsh as the login shell?" && sudo reboot || true
fi
