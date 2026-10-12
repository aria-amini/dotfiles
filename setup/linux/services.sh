#!/usr/bin/env bash

# Optional step catalog. Add a step here and define its label, probes, and phase below.
SETUP_STEPS=(docker tailscale pitchfork t3 wsl_interop)
T3_VERSION=0.0.45

setup_step_valid() {
  local step
  for step in "${SETUP_STEPS[@]}"; do
    [[ $1 != "$step" ]] || return 0
  done
  return 1
}

DOCKER_CLIENT_LINK=/usr/bin/docker

# Docker Desktop for Windows links its client into WSL. The link dangles while Desktop is stopped.
docker_installed() {
  command -v docker > /dev/null 2>&1 || [[ -L $DOCKER_CLIENT_LINK ]]
}

# Ubuntu derivatives report their own codename; Docker publishes the Ubuntu base codename.
ubuntu_codename() (
  # shellcheck source=/dev/null
  . "$HOST_OS_RELEASE"
  [[ ${ID:-} == ubuntu || ${ID_LIKE:-} == *ubuntu* ]] || die "Docker setup supports Ubuntu only (found ${ID:-unknown})"
  printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}"
)

docker_engine_installed() {
  command -v dockerd > /dev/null 2>&1
}

setup_step_available() {
  case "$1" in
  wsl_interop) host_is_wsl ;;
  *) return 0 ;;
  esac
}

# An explicit --with request replaces the defaults for services.
setup_step_default_selected() {
  local step="$1" requested="${2:-}"
  [[ $step != mise_tools ]] || return 0
  if [[ -n $requested ]]; then
    [[ ,$requested, == *,"$step",* ]]
    return
  fi
  case "$step" in
  docker) ! host_is_wsl ;;
  wsl_interop) return 1 ;;
  *) return 0 ;;
  esac
}

tailscale_installed() {
  command -v tailscale > /dev/null 2>&1 \
    || [[ "$(dpkg-query -W -f='${Status}' tailscale 2> /dev/null)" == 'install ok installed' ]]
}

t3_service_installed() {
  [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/t3code.service" ]]
}

setup_step_label() {
  case "$1" in
  mise_tools) printf 'Developer tools' ;;
  docker) printf 'Docker' ;;
  tailscale) printf 'Tailscale' ;;
  pitchfork) printf 'Pitchfork' ;;
  t3) printf 'T3 Code' ;;
  wsl_interop) printf 'WSL Windows PATH' ;;
  esac
}

setup_step_installed() {
  case "$1" in
  docker) docker_installed ;;
  tailscale) tailscale_installed ;;
  pitchfork) [[ -n "$(setup_step_version pitchfork)" ]] ;;
  t3) t3_service_installed ;;
  wsl_interop) wsl_windows_path_disabled ;;
  *) return 1 ;;
  esac
}

setup_step_version() {
  local field=1 line version
  local -a probe=() fields=()
  case "$1" in
  docker) probe=(docker --version); field=2 ;;
  tailscale) probe=(tailscale version); field=0 ;;
  pitchfork) probe=(pitchfork --version) ;;
  t3)
    if [[ -f "$HOME/.t3/runtime/service-state.json" ]]; then
      probe=(jq -er '.activeVersion // empty' "$HOME/.t3/runtime/service-state.json")
    else
      probe=(t3 --version)
    fi
    field=0
    ;;
  *) return 0 ;;
  esac
  # Version probes must not trigger downloads through mise shims.
  line="$(MISE_AUTO_INSTALL=false MISE_OFFLINE=true MISE_NO_ENV=true MISE_NO_HOOKS=true \
    timeout 5 "${probe[@]}" 2> /dev/null)" || return 0
  read -r -a fields <<< "$line"
  version="${fields[$field]:-}"
  [[ $version =~ ^v?[0-9] ]] || return 0
  printf '%s' "${version%,}"
}

: "${WSL_CONF:=/etc/wsl.conf}"

# git config is a section-aware INI editor; it keeps other sections and comments.
wsl_windows_path_disabled() {
  [[ "$(git config -f "$WSL_CONF" --type=bool --get interop.appendWindowsPath 2> /dev/null)" == false ]]
}

phase_wsl_interop() {
  run_task 'Disabling Windows PATH interop' --sudo \
    git config -f "$WSL_CONF" --replace-all interop.appendWindowsPath false
  NOTES+=("WSL interop: run 'wsl.exe --shutdown' on the Windows host to apply appendWindowsPath=false")
}

phase_docker() {
  if ! docker_installed; then
    local codename
    codename="$(ubuntu_codename)"
    run_task 'Creating the Docker key directory' --sudo install -m 0755 -d /etc/apt/keyrings
    run_task 'Downloading the Docker key' --sudo curl -fsSL --retry 3 \
      https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    run_task 'Setting Docker key permissions' --sudo chmod a+r /etc/apt/keyrings/docker.asc
    run_task 'Adding the Docker repository' --sudo tee /etc/apt/sources.list.d/docker.list \
      <<< "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable"
    run_task 'Updating the Docker package index' --sudo apt-get update
    run 'Installing Docker' --sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  show_version Docker 2 docker --version
  if ! docker_engine_installed; then
    detail 'docker client only (Docker Desktop); skipping group and service setup'
    return
  fi
  if ! id -nG "$USER" | grep -qw docker; then
    run_task 'Adding user to docker group' --sudo usermod -aG docker "$USER"
    NOTES+=('Docker group: log out and back in to run docker without sudo')
  fi
  if host_has_systemd; then
    run_task 'Enabling Docker' --sudo systemctl enable --now docker
  else
    detail 'no systemd; start dockerd manually with: sudo dockerd'
  fi
}

phase_tailscale() {
  if ! host_has_systemd; then
    detail 'no systemd; skipping Tailscale service setup'
    return
  fi
  need_sudo
  if ! tailscale_installed; then
    run_script 'Installing Tailscale' https://tailscale.com/install.sh sh
  fi
  show_version Tailscale 0 tailscale version
  run_task 'Enabling tailscaled' --sudo systemctl enable --now tailscaled
  if root_plain tailscale status > /dev/null 2>&1; then
    ok 'Tailscale authenticated'
  elif [[ $INTERACTIVE == true ]]; then
    detail 'Open the Tailscale login link below (timeout: 3 minutes)'
    if ! root_plain timeout 180 tailscale up; then
      warn "tailscale auth not completed; run 'sudo tailscale up' after install"
      return
    fi
  else
    warn "tailscale not authenticated; run 'sudo tailscale up' after install"
    return
  fi
  run_task 'Enabling Tailscale SSH' --sudo tailscale set --ssh=true || warn 'Tailscale SSH not enabled; check tailnet ACLs'
  run_task 'Setting Tailscale operator' --sudo tailscale set --operator="$USER" || warn 'Tailscale operator not set'
}

phase_pitchfork() {
  if ! host_has_systemd; then
    detail 'no systemd; skipping Pitchfork URL setup'
    return
  fi
  if [[ $SKIP_MANAGED_TOOLS == true ]]; then
    run 'Installing Pitchfork prerequisite' --live mise install pitchfork
  fi
  detail 'Pitchfork installs a boot service and a local TLS certificate authority'
  local pitchfork_bin ca
  pitchfork_bin="$(mise which pitchfork)"
  ca="${XDG_STATE_HOME:-$HOME/.local/state}/pitchfork/proxy/ca.pem"
  run_task 'Enabling user service lingering' --sudo loginctl enable-linger "$USER"
  run_task 'Enabling the Pitchfork boot service' "$pitchfork_bin" boot enable
  if ! "$pitchfork_bin" supervisor status > /dev/null 2>&1; then
    run_task 'Starting the Pitchfork supervisor' "$pitchfork_bin" supervisor start
  fi
  # The supervisor writes the proxy CA asynchronously after start.
  for _ in {1..20}; do
    [[ -f $ca ]] && break
    sleep 0.5
  done
  [[ -f $ca ]] || die "Pitchfork did not generate its CA certificate at $ca"
  if ! "$pitchfork_bin" proxy status | grep -q 'Trusted: yes'; then
    run_task 'Trusting the Pitchfork CA' --sudo "$pitchfork_bin" proxy trust
  fi
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
  if ! host_has_systemd; then
    detail 'no systemd; skipping T3 Code'
    return
  fi
  if [[ $SKIP_MANAGED_TOOLS == true ]]; then
    run 'Installing T3 Code prerequisites' --live mise install node opencode jq
  fi
  detail 'T3 Code installs a systemd user service for pairing remote devices'
  local opencode_bin t3_settings node_bin_dir
  opencode_bin="$(mise -C "$DOTFILES_DIR" which opencode)"
  t3_settings="$HOME/.t3/userdata/settings.json"
  if [[ ! -f "$t3_settings" ]]; then
    write_t3_settings "$opencode_bin" "$t3_settings"
  fi
  node_bin_dir="$(dirname "$(mise -C "$DOTFILES_DIR" which node)")"
  if [[ ! -x /usr/bin/g++ ]]; then
    run_task 'Installing build tools' --sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
  fi
  local action=Installing
  ! t3_service_installed || action=Updating
  run_task "$action T3 Code" env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ \
    NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" "$node_bin_dir/npx" --yes "t3@$T3_VERSION" service install
  if [[ $action == Installing ]]; then
    NOTES+=($'Pair a device:\n  t3 pair --tailscale --tailscale-serve-port 8443\n  then scan the QR code')
  fi
}
