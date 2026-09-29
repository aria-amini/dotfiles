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
quick) FLAGS+=(--minimal --skip mise_install --skip herdr_jj_workspaces) ;;
full) ;;
*)
  echo "usage: inside.sh [quick|full]" >&2
  exit 2
  ;;
esac

sudo -iu dev bash /src/install.sh "${FLAGS[@]}"

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

grep -q 'local/share/mise/shims' ~/.profile || fail ".profile missing mise shims"
grep -q 'nix-profile' ~/.profile || fail ".profile missing nix"
grep -q '.local/bin' ~/.profile || fail ".profile missing ~/.local/bin"

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

for tool in uv gh hunk opencode herdr jj node; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH in login shell"
done
ASSERT_FULL
fi

echo "E2E ($MODE) PASSED"
