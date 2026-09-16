#!/bin/sh
[ -d "$HOME/.config/tmux/plugins/tpm" ] && exit 0
git clone --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
