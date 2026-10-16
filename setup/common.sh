#!/usr/bin/env bash

fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$@"
}

AGE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"
AGE_KEY="$AGE_DIR/age-key.txt"
AGE_CONFIG="$AGE_DIR/chezmoi.toml"

has_encrypted_sources() {
  find "$DOTFILES_DIR" \( -name .git -o -name .jj \) -prune -o -name '*.age' -print -quit | grep -q .
}

age_key_valid() {
  chezmoi age-keygen -y "$AGE_KEY" > /dev/null 2>&1
}

restore_age_key() {
  local source="${DOTFILES_AGE_KEY_FILE:-}" line
  mkdir -p "$AGE_DIR"
  if [[ -n $source ]]; then
    [[ -s $source ]] || {
      echo "DOTFILES_AGE_KEY_FILE is missing or empty: $source" >&2
      return 1
    }
    install -m 600 "$source" "$AGE_KEY"
    age_key_valid || {
      rm -f "$AGE_KEY"
      echo "Age key is invalid: $source" >&2
      return 1
    }
    return
  fi
  [[ ${DOTFILES_ASSUME_YES:-false} != true && -t 0 && -t 1 ]] || return 1
  printf 'Paste the AGE-SECRET-KEY line (hidden), or press Enter to skip: ' >&2
  IFS= read -rs line
  printf '\n' >&2
  [[ $line == AGE-SECRET-KEY-* ]] || return 1
  (umask 077 && printf '%s\n' "$line" > "$AGE_KEY")
  age_key_valid || {
    rm -f "$AGE_KEY"
    echo 'Age key is invalid.' >&2
    return 1
  }
}

configure_age() {
  local recipient
  recipient="$(chezmoi age-keygen -y "$AGE_KEY")" || return 1
  if [[ -e $AGE_CONFIG ]]; then
    grep -Eq '^encryption *= *"age"' "$AGE_CONFIG" \
      && grep -Eq '^identity *=' "$AGE_CONFIG" && return 0
    printf 'Add to %s, before all sections:\nencryption = "age"\n[age]\nidentity = "%s"\nrecipient = "%s"\n' \
      "$AGE_CONFIG" "$AGE_KEY" "$recipient" >&2
    return 1
  fi
  (umask 077 && printf 'encryption = "age"\n\n[age]\nidentity = "%s"\nrecipient = "%s"\n' \
    "$AGE_KEY" "$recipient" > "$AGE_CONFIG")
}

# Encrypted credentials stay ignored until age works. Never fail setup over them.
ensure_age_identity() {
  has_encrypted_sources || return 0
  if [[ ! -s $AGE_KEY ]] || ! age_key_valid; then
    restore_age_key || true
  fi
  if [[ -s $AGE_KEY ]] && age_key_valid && configure_age; then
    return 0
  fi
  echo "Encrypted credentials skipped. Restore the age key, then rerun with DOTFILES_AGE_KEY_FILE=<path> or configure age by hand." >&2
}

apply_dotfiles() {
  ensure_age_identity
  local -a args=(--source "$DOTFILES_DIR")
  if [[ ${DOTFILES_ASSUME_YES:-false} == true || ! -t 0 || ! -t 1 ]]; then
    args+=(--no-tty --error-on-conflict)
  fi
  args+=(apply)
  printf 'chezmoi %s\n' "${args[*]}"
  chezmoi "${args[@]}"
}
