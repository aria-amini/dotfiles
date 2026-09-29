#!/usr/bin/env bash
# Runs inside a fresh ubuntu:24.04 container with the repo mounted at /src.
# Usage: inside.sh [quick|full]
set -Eeuo pipefail

MODE="${1:-quick}"
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq sudo curl git ca-certificates > /dev/null

if ! id dev > /dev/null 2>&1; then
  useradd -m -s /bin/bash dev
fi
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
chmod 440 /etc/sudoers.d/dev

FLAGS=(--verbose --non-interactive --source /src)
case "$MODE" in
  quick)
    FLAGS+=(--minimal --skip mise_tools)
    ENV_FLAGS=(DOTFILES_SKIP_TOOLS=1)
    ;;
  full) ENV_FLAGS=() ;;
*)
  echo "usage: inside.sh [quick|full]" >&2
  exit 2
  ;;
esac

sudo -iu dev env "${ENV_FLAGS[@]}" bash /src/install.sh "${FLAGS[@]}"

# Assert via a bash login shell: exercises the managed .profile (nix,
# ~/.local/bin, mise shims) without depending on zsh's interactive hooks.
sudo -iu dev env SOURCE_DIR="/src" bash -l -s << 'ASSERT'
set -euo pipefail

fail() {
  echo "ASSERT FAIL: $*" >&2
  exit 1
}

for tool in gum chezmoi mise nix zsh git curl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH in login shell"
done

[[ "$(getent passwd dev | cut -d: -f7)" == "$(command -v zsh)" ]] ||
  fail "zsh is not the default shell"

grep -q 'local/share/mise/shims' ~/.bash_profile ||
  fail ".bash_profile missing mise shims"
grep -q 'nix-profile\|.profile' ~/.bash_profile ||
  fail ".bash_profile missing nix chain"
grep -q '.local/bin' ~/.bash_profile ||
  fail ".bash_profile missing ~/.local/bin"

[[ -f "$SOURCE_DIR/install.sh" && -f "$SOURCE_DIR/home/.chezmoiignore" ]] ||
  fail "dotfiles source unreadable"

[[ -d ~/.ssh/devboxes.d ]] || fail "~/.ssh/devboxes.d missing"
[[ -s ~/.config/chezmoi/chezmoi.toml ]] || fail "chezmoi config missing"
grep -q 'sourceDir' ~/.config/chezmoi/chezmoi.toml || fail "chezmoi sourceDir missing"

pager="$(git config --get core.pager)"
printf x | env PATH=/usr/bin:/bin sh -c "$pager" >/dev/null ||
  fail "core.pager unusable without mise: $pager"
ASSERT

if [[ "$MODE" == "full" ]]; then
  sudo -iu dev env SOURCE_DIR="/src" bash -l -s << 'ASSERT_FULL'
set -euo pipefail

fail() {
  echo "ASSERT FAIL: $*" >&2
  exit 1
}

for tool in uv gh hunk opencode herdr jj node herdr-jj; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH in login shell"
done
[[ -d ~/tools/herdr-jj-workspaces/.git ]] || fail "tools repo not cloned"
herdr plugin list 2>/dev/null | grep -q aamini.jj || fail "aamini.jj plugin not installed"
ASSERT_FULL
fi

echo "E2E ($MODE) PASSED"
