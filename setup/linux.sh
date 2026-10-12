#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE="${DOTFILES_PROFILE:-full}"
ASSUME_YES="${DOTFILES_ASSUME_YES:-false}"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OPTIONAL_STEPS="${DOTFILES_WITH:-}"
SKIP_MANAGED_TOOLS="${DOTFILES_SKIP_MANAGED_TOOLS:-false}"

# shellcheck source=setup/common.sh
source "$DOTFILES_DIR/setup/common.sh"
# shellcheck source=setup/linux/host.sh
source "$DOTFILES_DIR/setup/linux/host.sh"
# shellcheck source=setup/linux/runtime.sh
source "$DOTFILES_DIR/setup/linux/runtime.sh"
# shellcheck source=setup/linux/tools.sh
source "$DOTFILES_DIR/setup/linux/tools.sh"
# shellcheck source=setup/linux/services.sh
source "$DOTFILES_DIR/setup/linux/services.sh"

validate_optional_steps() {
  case "$SKIP_MANAGED_TOOLS" in
  true | false) ;;
  *) die 'DOTFILES_SKIP_MANAGED_TOOLS must be true or false' ;;
  esac
  local step expected
  local -a steps
  printf -v expected '%s, ' "${SETUP_STEPS[@]}"
  IFS=, read -r -a steps <<< "$OPTIONAL_STEPS"
  for step in "${steps[@]}"; do
    setup_step_valid "$step" || die "unknown optional step: $step (expected ${expected%, })"
    setup_step_available "$step" || die "optional step is not available on this host: $step"
  done
  [[ $PROFILE == full || -z $OPTIONAL_STEPS ]] || die '--with requires the full profile'
}

choose_setup_steps() {
  local selection label step status version action row header requested="$OPTIONAL_STEPS"
  local -a selected=() options=()
  local -a ready=()
  for step in mise_tools "${SETUP_STEPS[@]}"; do
    setup_step_available "$step" || continue
    label="$(setup_step_label "$step")"
    if setup_step_installed "$step"; then
      version="$(setup_step_version "$step")"
      printf -v row '    ✓ %-20s %-28s %s' "$label" "${version:-Version unavailable}" 'Ready'
      ready+=("$row")
      continue
    fi
    action=Install
    case "$step" in
    mise_tools)
      status="$(managed_tools_status)"
      [[ $status != *'; sync' ]] || action=Sync
      status="${status%%;*}"
      ;;
    *) status='Not installed' ;;
    esac
    printf -v row '%-20s %-28s %s' "$label" "$status" "$action"
    options+=("$row|$step")
    [[ $step != mise_tools || $SKIP_MANAGED_TOOLS != true ]] || continue
    ! setup_step_default_selected "$step" "$requested" || selected+=("$row")
  done
  printf -v row '      %-20s %-28s %s' 'Tool' 'Version / Status' 'Action'
  header="$row"
  for row in "${ready[@]}"; do
    header+=$'\n\033[38;5;82m'"$row"$'\033[0m'
  done
  header+=$'\n\nChoose setup steps'
  selection="$(gum_ui choose --no-limit --label-delimiter '|' --header "$header" \
    --cursor-prefix '[ ] ' --selected-prefix '[x] ' --unselected-prefix '[ ] ' \
    --selected "$(IFS=,; printf '%s' "${selected[*]}")" \
    "${options[@]}" < /dev/tty 2> /dev/tty)" || return $?
  OPTIONAL_STEPS=''
  SKIP_MANAGED_TOOLS=true
  while IFS= read -r step; do
    if [[ $step == mise_tools ]]; then
      SKIP_MANAGED_TOOLS=false
    elif setup_step_valid "$step"; then
      OPTIONAL_STEPS+=",$step"
    fi
  done <<< "$selection"
  OPTIONAL_STEPS="${OPTIONAL_STEPS#,}"
}

configure_sections() {
  if [[ $PROFILE == full && $INTERACTIVE == true ]]; then
    choose_setup_steps
  fi
  SECTIONS=('System|apt git mise nix' 'Dotfiles|dotfiles')
  if [[ $PROFILE == full ]]; then
    [[ $SKIP_MANAGED_TOOLS == true ]] || SECTIONS+=('Developer Tools|mise_tools')
    local services='' service
    for service in "${SETUP_STEPS[@]}"; do
      [[ ,$OPTIONAL_STEPS, != *,"$service",* ]] || services+=" $service"
    done
    [[ -z $services ]] || SECTIONS+=("Services|${services# }")
  fi
  SECTIONS+=('Summary|shell github_notice')
}

main() {
  [[ "$(uname -s)" == Linux ]] || die 'this setup supports Linux only'
  case "$PROFILE" in
  core | full) ;;
  *) die "unknown profile: $PROFILE (expected core or full)" ;;
  esac
  validate_optional_steps
  case "$(uname -m)" in
  x86_64 | aarch64) ;;
  *) die "unsupported arch: $(uname -m)" ;;
  esac
  command -v curl > /dev/null 2>&1 || die 'curl is required'
  cd "$HOME"
  if [[ -t 1 && $ASSUME_YES == false ]]; then
    INTERACTIVE=true
  fi
  LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-setup-XXXXXX.log")"
  trap on_err ERR
  exec > >(tee -a "$LOG_FILE") 2>&1
  printf 'transcript: %s\n' "$LOG_FILE"
  CURRENT_PHASE=gum
  phase_gum
  CURRENT_PHASE=options
  configure_sections
  if [[ $SKIP_MANAGED_TOOLS == true ]]; then
    # Mise task and shim auto-installs can otherwise bypass the catalog skip.
    export MISE_AUTO_INSTALL=false
  fi
  local entry phase
  local -a section_phases
  for entry in "${SECTIONS[@]}"; do
    section_begin "${entry%%|*}"
    read -r -a section_phases <<< "${entry#*|}"
    for phase in "${section_phases[@]}"; do
      CURRENT_PHASE="$phase"
      "phase_$phase"
    done
  done
  ui style --border rounded --border-foreground 82 --padding '0 3' --margin '1 0' '✓ Setup complete'
  local note
  for note in "${NOTES[@]+"${NOTES[@]}"}"; do
    ui style --foreground 214 "$note"
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main
fi
