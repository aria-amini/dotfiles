#!/usr/bin/env bash
set -Eeuo pipefail
cd "$HOME"

GUM_VERSION="0.16.1"
DOTFILES_REPO="https://github.com/aria-amini/dotfiles.git"
TOOLS_REPO="https://github.com/aria-amini/tools"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
SYNC_DOTFILES=true
LOG_FILE="${TMPDIR:-/tmp}/dotfiles-install-$(date +%Y%m%d-%H%M%S).log"

PHASES=(gum apt git mise gh dotfiles nix chezmoi mise_install herdr_jj_workspaces docker tailscale pitchfork t3 shell)
MINIMAL_SKIPS=(docker tailscale pitchfork t3)

VERBOSE=false
NON_INTERACTIVE=false
DRY_RUN=false
SKIP=()
NOTES=()
CURRENT_PHASE=startup
PHASE_NO=0
PHASE_TOTAL=0
SUMMARY_SHELL_CHANGED=false

usage() {
  cat << 'EOF'
Usage: install.sh [options]

Options:
  --verbose          plain output, full transcript to a log file
  --non-interactive  never prompt; defer anything needing input
  --dry-run          print actions without running them
  --minimal          skip docker, tailscale, pitchfork, t3
  --skip PHASE       skip one phase (repeatable)
  --source DIR       use DIR as the dotfiles source without cloning or syncing
  -h, --help         show this help

Phases: gum apt git mise gh dotfiles nix chezmoi mise_install
        herdr_jj_workspaces docker tailscale pitchfork t3 shell
EOF
}

while (($#)); do
  case "$1" in
  --verbose) VERBOSE=true ;;
  --non-interactive) NON_INTERACTIVE=true ;;
  --dry-run) DRY_RUN=true ;;
  --minimal) SKIP+=("${MINIMAL_SKIPS[@]}") ;;
  --skip)
    [[ -n "${2:-}" ]] || {
      usage >&2
      exit 2
    }
    SKIP+=("$2")
    shift
    ;;
    --skip=*) SKIP+=("${1#--skip=}") ;;
    --source)
      [[ -n "${2:-}" ]] || { usage >&2; exit 2; }
      DOTFILES_DIR="$2"
      SYNC_DOTFILES=false
      shift
      ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
  shift
done

INTERACTIVE=false
if [[ -t 1 && $NON_INTERACTIVE == false ]]; then
  INTERACTIVE=true
fi

IS_WSL=false
if grep -qi microsoft /proc/version 2> /dev/null; then
  IS_WSL=true
fi

HAS_SYSTEMD=false
if [[ -d /run/systemd/system ]]; then
  HAS_SYSTEMD=true
fi

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  die "this installer supports Linux only"
fi
case "$(uname -m)" in
x86_64 | aarch64) ;;
*) die "unsupported arch: $(uname -m)" ;;
esac
command -v curl > /dev/null 2>&1 || die "curl is required: sudo apt-get install curl"

if [[ $VERBOSE == true && $DRY_RUN == false ]]; then
  exec > >(tee "$LOG_FILE") 2>&1
  printf 'transcript: %s\n' "$LOG_FILE"
fi

on_err() {
  local rc=$?
  printf '✗ Failed during: %s (exit %s)\n' "$CURRENT_PHASE" "$rc" >&2
  printf '  command: %s\n' "$BASH_COMMAND" >&2
  if [[ $VERBOSE == true && $DRY_RUN == false ]]; then
    printf '  transcript: %s\n' "$LOG_FILE" >&2
  else
    printf '  re-run with --verbose for a full transcript\n' >&2
  fi
}
trap on_err ERR

# Renders gum style args; falls back to the positional text when gum is
# unavailable (--dry-run before the gum phase).
ui() {
  if command -v gum > /dev/null 2>&1; then
    gum "$@"
    return
  fi
  printf '%s\n' "${*: -1}"
}

title() {
  if command -v gum > /dev/null 2>&1; then
    gum style --border double --border-foreground 212 --padding "1 3" --margin "1 0" \
      --align center --width 44 \
      "$(gum style --bold --foreground 212 'dotfiles')" \
      "github.com/aria-amini/dotfiles"
  else
    printf '\n════════ dotfiles — github.com/aria-amini/dotfiles ════════\n'
  fi
}

phase_begin() {
  CURRENT_PHASE="$1"
  PHASE_NO=$((PHASE_NO + 1))
  printf '\n▸ [%s/%s] %s\n' "$PHASE_NO" "$PHASE_TOTAL" "$1"
}

ok() {
  local line
  if [[ -n "${2:-}" ]]; then
    printf -v line '  ✓ %-22s %s' "$1" "$2"
  else
    line="  ✓ $1"
  fi
  ui style --foreground 82 "$line"
}

detail() {
  local line
  printf -v line '    %-22s %s' "" "$1"
  ui style --foreground 245 "$line"
}

warn() {
  ui style --foreground 214 "  ! $1"
  NOTES+=("$1")
}

show_version() {
  [[ $DRY_RUN == true ]] && return 0
  local label="$1" field="$2" line=""
  shift 2
  command -v "$1" > /dev/null 2>&1 || return 0
  IFS= read -r line < <("$@" 2>&1) || true
  [[ -n "$line" ]] || return 0
  local -a fields
  read -r -a fields <<<"$line"
  ok "$label" "${fields[$field]:-}"
}

fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$@"
}

run() {
  local label="$1"
  shift
  if [[ $DRY_RUN == true ]]; then
    printf '  [dry-run] %s: %s\n' "$label" "$*"
    return 0
  fi
  if [[ $VERBOSE == true ]]; then
    printf '  $ %s\n' "$*"
    "$@"
  else
    gum spin --show-error --title "  $label..." -- "$@"
  fi
}

run_task() {
  local label="$1"
  shift
  run "$label" "$@"
  ok "$label"
}

run_plain() {
  if [[ $DRY_RUN == true ]]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

need_sudo() {
  if [[ $EUID -eq 0 ]]; then
    return
  fi
  command -v sudo > /dev/null 2>&1 || die "sudo not found; install sudo or run as root"
  if sudo -n true 2> /dev/null; then
    return
  fi
  [[ $INTERACTIVE == true ]] || die "sudo needs a password; run interactively or pre-cache credentials with 'sudo -v'"
  detail "requesting administrator authentication"
  sudo -v
}

git_at_least() {
  local have
  command -v git > /dev/null 2>&1 || return 1
  have="$(git --version 2> /dev/null | awk 'NR==1{print $3}')"
  [[ -n "$have" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$have" "$1" | sort -V | head -n1)" == "$1" ]]
}

phase_gum() {
  phase_begin gum
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v gum > /dev/null 2>&1; then
    local arch gum_arch
    mkdir -p "$HOME/.local/bin"
    arch="$(uname -m)"
    case "$arch" in
    x86_64) gum_arch="x86_64" ;;
    aarch64) gum_arch="arm64" ;;
    *) die "unsupported arch: $arch" ;;
    esac
    run_task "Installing gum" bash -c "
      curl -fsSL --retry 3 'https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_${gum_arch}.tar.gz' |
        tar -xz -C /tmp 'gum_${GUM_VERSION}_Linux_${gum_arch}/gum' &&
      mv '/tmp/gum_${GUM_VERSION}_Linux_${gum_arch}/gum' '$HOME/.local/bin/gum'
    "
  fi
  title
  show_version "Gum" 2 "$HOME/.local/bin/gum" --version
}

phase_apt() {
  phase_begin apt
  need_sudo
  local attempt
  for attempt in 1 2 3; do
    if run "Updating package index" sudo apt-get update; then
      break
    fi
    if [[ $attempt == 3 ]]; then
      return 1
    fi
    warn "apt-get update failed; retrying ($attempt/3)"
    sleep 2
  done
  run_task "Installing base packages" \
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    software-properties-common xz-utils zsh curl ca-certificates
  show_version "Zsh" 1 zsh --version
  if [[ $IS_WSL == true ]] && ! grep -qs 'appendWindowsPath=false' /etc/wsl.conf; then
    run_task "Disabling Windows PATH interop" \
      bash -c "printf '\n[interop]\nappendWindowsPath=false\n' | sudo tee -a /etc/wsl.conf >/dev/null"
    NOTES+=("WSL interop: run 'wsl.exe --shutdown' on the Windows host to apply appendWindowsPath=false")
  fi
}

phase_git() {
  phase_begin git
  if git_at_least 2.41; then
    show_version "Git" 2 git --version
    return
  fi
  need_sudo
  run_task "Installing Git from ppa:git-core" bash -c '
    sudo add-apt-repository -y ppa:git-core/ppa
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git
  '
  git_at_least 2.41 || {
    [[ $DRY_RUN == true ]] && return
    die "git >= 2.41 required after ppa install"
  }
  show_version "Git" 2 git --version
}

phase_mise() {
  phase_begin mise
  if ! command -v mise > /dev/null 2>&1; then
    run_task "Installing mise" bash -c 'curl -fsSL --retry 3 https://mise.run | sh'
  fi
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  show_version "Mise" 0 mise --version
}

phase_gh() {
  phase_begin gh
  if ! command -v gh > /dev/null 2>&1; then
    run_task "Installing GitHub CLI" mise install --quiet github-cli
  fi
  show_version "GitHub CLI" 2 gh --version
  if gh auth status > /dev/null 2>&1; then
    ok "GitHub authenticated" "$(gh api user --jq .login 2> /dev/null || true)"
  elif [[ $INTERACTIVE == true ]]; then
    detail "authenticating with GitHub"
    run_plain gh auth login --web --git-protocol https < /dev/tty
  else
    warn "gh not authenticated; run 'gh auth login --web' and re-run this installer for private-repo steps"
  fi
}

phase_dotfiles() {
  phase_begin dotfiles
  if [[ $SYNC_DOTFILES == false ]]; then
    ok "Dotfiles" "$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2> /dev/null || true)"
    return
  fi
  if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    run_task "Cloning dotfiles" git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  else
    run "Fetching dotfiles" git -C "$DOTFILES_DIR" fetch origin main
    run "Resetting dotfiles to origin/main" git -C "$DOTFILES_DIR" reset --hard FETCH_HEAD
  fi
  ok "Dotfiles" "$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2> /dev/null || true)"
}

phase_nix() {
  phase_begin nix
  if ! command -v nix > /dev/null 2>&1; then
    run_task "Installing Nix" bash -c "sh <(curl --proto '=https' --tlsv1.2 -sSL https://nixos.org/nix/install) --no-daemon"
  fi
  if [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck source=/dev/null
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
  if [[ $DRY_RUN == true ]]; then
    return
  fi
  command -v nix > /dev/null 2>&1 || die "nix not on PATH after install"
  show_version "Nix" 2 nix --version
}

phase_chezmoi() {
  phase_begin chezmoi
  if ! command -v chezmoi > /dev/null 2>&1; then
    if [[ $DRY_RUN == true ]]; then
      printf '  [dry-run] Installing chezmoi: sh -c <(curl -fsLS get.chezmoi.io) -- -b %s\n' "$HOME/.local/bin"
    else
      run_task "Installing chezmoi" sh -c "$(fetch https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
    fi
  fi
  show_version "Chezmoi" 2 chezmoi --version
  if [[ ! -s "$HOME/.config/chezmoi/chezmoi.toml" ]]; then
    run_task "Seeding chezmoi config" bash -c \
      "mkdir -p '$HOME/.config/chezmoi' && printf 'sourceDir = \"%s\"\n' '$DOTFILES_DIR' > '$HOME/.config/chezmoi/chezmoi.toml'"
  fi
  detail "applying dotfiles"
  # chezmoi init re-executes .chezmoi.toml.tmpl without previous-config data,
  # so promptStringOnce would prompt even with a seeded config. The seeded
  # config makes apply equivalent and prompt-free.
  run "Applying dotfiles" chezmoi apply --source "$DOTFILES_DIR"
  ok "Applying dotfiles"
}

phase_mise_install() {
  phase_begin mise_install
  run_task "Installing managed tools" mise install --quiet
  ok "Managed tools" "$(mise ls 2> /dev/null | grep -c '^[a-z]' || true) tools"
}

phase_herdr_jj_workspaces() {
  phase_begin herdr_jj_workspaces
  local repo="$HOME/tools/herdr-jj-workspaces"
  local pkg="$repo/herdr-jj-workspaces"
  local plugin="$repo/herdr-plugin"
  if ! gh auth status > /dev/null 2>&1; then
    warn "gh not authenticated; skipping herdr-jj-workspaces (authenticate, then re-run this installer)"
    return
  fi
  if [[ ! -d "$repo/.git" ]]; then
    run_task "Cloning tools monorepo" git clone "$TOOLS_REPO" "$repo"
  fi
  [[ -d "$pkg" ]] || die "herdr-jj-workspaces package not found at $pkg"
  run_task "Installing herdr-jj-workspaces" uv tool install --python 3.14 --editable --reinstall "$pkg"
  run_task "Linking herdr-jj-workspaces plugin" herdr plugin link "$plugin"
}

phase_docker() {
  phase_begin docker
  if ! command -v docker > /dev/null 2>&1; then
    run_task "Installing Docker" bash -c '
      sudo install -m 0755 -d /etc/apt/keyrings
      sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      sudo chmod a+r /etc/apt/keyrings/docker.asc
      . /etc/os-release
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    '
  fi
  show_version "Docker" 2 docker --version
  if id -nG "$USER" | grep -qw docker; then
    ok "Docker group"
  else
    run_task "Adding user to docker group" sudo usermod -aG docker "$USER"
    NOTES+=("Docker group: log out and back in to run docker without sudo")
  fi
  if [[ $HAS_SYSTEMD == true ]]; then
    run_task "Enabling Docker" sudo systemctl enable --now docker
  else
    detail "no systemd; start dockerd manually with: sudo dockerd"
  fi
}

phase_tailscale() {
  phase_begin tailscale
  if [[ $HAS_SYSTEMD == false ]]; then
    detail "no systemd; skipping (manual daemon: mise -C ~/dotfiles run tailscaled)"
    return
  fi
  need_sudo
  if ! dpkg -s tailscale > /dev/null 2>&1; then
    run_task "Installing Tailscale" bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'
  else
    ok "Tailscale"
  fi
  run_task "Enabling tailscaled" sudo systemctl enable --now tailscaled
  if sudo tailscale status > /dev/null 2>&1; then
    ok "Tailscale authenticated"
  elif [[ $INTERACTIVE == true ]]; then
    warn "Tailscale authentication required; open the login link printed next"
    run_plain sudo tailscale up
  else
    warn "tailscale not authenticated; run 'sudo tailscale up' after install"
    return
  fi
  run_task "Enabling Tailscale SSH" sudo tailscale set --ssh=true ||
    warn "Tailscale SSH not enabled; check tailnet ACLs"
  run_task "Setting Tailscale operator" sudo tailscale set --operator="$USER" ||
    warn "Tailscale operator not set"
}

phase_pitchfork() {
  phase_begin pitchfork
  if [[ $HAS_SYSTEMD == false ]]; then
    detail "no systemd; skipping Pitchfork URL setup"
    return
  fi
  local pitchfork_host="${PITCHFORK_PROXY_HOST:-}" pitchfork_access=""
  if [[ -z "$pitchfork_host" && $INTERACTIVE == true && $DRY_RUN == false ]]; then
    pitchfork_access="$(gum choose --header "Where will you open local app URLs?" \
      "On this machine" "From another machine" < /dev/tty)"
    if [[ "$pitchfork_access" == "From another machine" ]]; then
      pitchfork_host="0.0.0.0"
    else
      pitchfork_host="127.0.0.1"
    fi
  fi
  if [[ -z "$pitchfork_host" ]]; then
    pitchfork_host="127.0.0.1"
  fi
  detail "Pitchfork installs a boot service and a local TLS certificate authority"
  run_task "Configuring Pitchfork URLs" mise -C "$HOME/dotfiles" run setup-pitchfork "$pitchfork_host"
}

phase_t3() {
  phase_begin t3
  if [[ $HAS_SYSTEMD == false ]]; then
    detail "no systemd; skipping T3 Code"
    return
  fi
  local opencode_bin t3_settings node_bin_dir
  opencode_bin="$(mise -C "$HOME/dotfiles" which opencode)"
  t3_settings="$HOME/.t3/userdata/settings.json"
  if [[ ! -f "$t3_settings" ]]; then
    run_task "Writing T3 Code settings" bash -c \
      "mkdir -p '$HOME/.t3/userdata' && jq -n --arg b '$opencode_bin' '{providers: {opencode: {enabled: true, binaryPath: \$b}}}' > '$t3_settings'"
  fi
  node_bin_dir="$(dirname "$(mise -C "$HOME/dotfiles" which node)")"
  if [[ ! -x /usr/bin/g++ ]]; then
    need_sudo
    run_task "Installing build tools" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential
  fi
  if [[ -f "$HOME/.config/systemd/user/t3code.service" ]]; then
    run_task "Updating T3 Code" env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ \
      NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" "$node_bin_dir/npx" --yes t3@0.0.40 service update
  else
    run_task "Installing T3 Code" env PATH="$node_bin_dir:/usr/bin:/bin" CC=/usr/bin/gcc CXX=/usr/bin/g++ \
      NPM_CONFIG_CACHE="$HOME/.cache/npm-t3" "$node_bin_dir/npx" --yes t3@0.0.40 service install
    NOTES+=($'Pair a device:\n  t3 pair --tailscale --tailscale-serve-port 8443\n  then scan the QR code')
  fi
}

phase_shell() {
  phase_begin shell
  if [[ $DRY_RUN == true ]]; then
    detail "dry-run: would set zsh as the default shell if needed"
    return
  fi
  local zsh_path shell_changed=false
  zsh_path="$(command -v zsh)"
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$zsh_path" ]]; then
    ok "Zsh is the default shell"
  else
    need_sudo
    run_task "Setting Zsh as the default shell" sudo usermod -s "$zsh_path" "$USER"
    shell_changed=true
  fi
  SUMMARY_SHELL_CHANGED=$shell_changed
}

finish() {
  ui style --border rounded --border-foreground 82 --padding "0 3" --margin "1 0" \
    --foreground 82 "✓ Install complete"
  local note
  for note in "${NOTES[@]+"${NOTES[@]}"}"; do
    ui style --border rounded --border-foreground 214 --padding "0 3" --margin "1 0" \
      --foreground 214 "$note"
  done
  if [[ $DRY_RUN == false && $SUMMARY_SHELL_CHANGED == true && $INTERACTIVE == true && $IS_WSL == false ]]; then
    if gum confirm "Reboot now to apply zsh as the login shell?" < /dev/tty; then
      run_plain sudo reboot
    fi
  fi
}

RUN=()
for p in "${PHASES[@]}"; do
  skip_this=false
  for s in "${SKIP[@]+"${SKIP[@]}"}"; do
    if [[ "$s" == "$p" ]]; then
      skip_this=true
    fi
  done
  if [[ $skip_this == false ]]; then
    RUN+=("$p")
  fi
done
PHASE_TOTAL=${#RUN[@]}

for p in "${RUN[@]}"; do
  "phase_$p"
done
finish
