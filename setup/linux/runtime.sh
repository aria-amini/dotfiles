#!/usr/bin/env bash

GUM_VERSION="0.16.2"
LOG_FILE=''
INTERACTIVE=false
NOTES=()
CURRENT_PHASE=startup
SECTION_NO=0

die() {
  printf '✗ %s\n' "$*" >&2
  exit 1
}

on_err() {
  local rc=$?
  printf '✗ Failed during: %s (exit %s)\n' "$CURRENT_PHASE" "$rc" >&2
  printf '  command: %s\n  transcript: %s\n' "$BASH_COMMAND" "$LOG_FILE" >&2
}

gum_ui() {
  # This palette avoids the OSC/CPR theme probes that can leak replies into shell input.
  TERM=screen-256color gum "$@"
}

ui() {
  if [[ $INTERACTIVE == true ]] && command -v gum > /dev/null 2>&1; then
    gum_ui "$@" > /dev/tty 2>&1 || return $?
    if [[ -n $LOG_FILE ]]; then
      printf '%s\n' "${*: -1}" >> "$LOG_FILE"
    fi
    return 0
  fi
  printf '%s\n' "${*: -1}"
}

title() {
  ui style --border double --border-foreground 212 --padding '1 3' --margin '1 0' \
    --align center --width 44 $'dotfiles\ngithub.com/aria-amini/dotfiles'
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
  local version="${fields[$field]:-}"
  ok "$label" "${version%,}"
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
  local live=false
  if [[ ${1:-} == --live ]]; then
    live=true
    shift
  fi
  if [[ ${1:-} == --sudo ]]; then
    shift
    need_sudo || return $?
    if [[ $EUID -ne 0 ]]; then
      set -- sudo "$@"
    fi
  fi
  if [[ $INTERACTIVE == false ]] || ! command -v gum > /dev/null 2>&1; then
    printf '  $ %s\n' "$*"
    "$@"
    return
  fi
  local log rc
  log="$(mktemp "${TMPDIR:-/tmp}/dotfiles-run-XXXXXX")"
  if [[ $live == true ]]; then
    run_live "$label" "$log" "$@" || rc=$?
  else
    # The transcript pipe hides the terminal from Gum. Keep animations on the TTY.
    # shellcheck disable=SC2016
    gum_ui spin --title "  $label..." -- \
      bash -c 'exec "$2" "${@:3}" >"$1" 2>&1' _ "$log" "$@" \
      > /dev/tty 2>&1 || rc=$?
  fi
  if [[ -n $LOG_FILE ]]; then
    cat "$log" >> "$LOG_FILE"
  fi
  if [[ ${rc:-0} != 0 ]]; then
    cat "$log" > /dev/tty
  fi
  rm -f "$log"
  return "${rc:-0}"
}

run_live() (
  local label="$1" log="$2" pid rc=0 rows=0 width line
  shift 2
  width="$(tput cols 2> /dev/null || printf '80')"
  width=$((width > 1 ? width - 1 : 1))
  "$@" > "$log" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
    { ((rows == 0)) || printf "\033[%sA" "$rows"; printf "\r\033[J"; } > /dev/tty' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while kill -0 "$pid" 2> /dev/null; do
    {
      ((rows == 0)) || printf '\033[%sA' "$rows"
      printf '\r\033[J'
      line="  $label..."
      printf '%s\n' "${line:0:width}"
      rows=1
      # Command escape sequences can move the cursor outside the temporary viewport.
      while IFS= read -r line; do
        printf '    %s\n' "${line:0:width > 4 ? width - 4 : 0}"
        rows=$((rows + 1))
      done < <(tail -n 8 "$log" | sed -E $'s/\033\\[[0-?]*[ -/]*[@-~]//g; s/[[:cntrl:]]//g')
    } > /dev/tty
    sleep 0.1
  done
  wait "$pid" || rc=$?
  trap - EXIT
  {
    ((rows == 0)) || printf '\033[%sA' "$rows"
    printf '\r\033[J'
  } > /dev/tty
  return "$rc"
)

run_task() {
  local label="$1"
  run "$@" || return $?
  ok "$label"
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

root_plain() {
  need_sudo || return $?
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

phase_gum() {
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
}
