#!/usr/bin/env bash

set -uo pipefail

fail() {
	printf '%s\nPress any key to close.\n' "$1" >&2
	read -r -n 1 -s || true
	exit 1
}

if [ "${1:-}" != add-from-sesh ]; then
	printf 'Usage: %s add-from-sesh <entry>\n' "$0" >&2
	exit 2
fi

entry=${2:-}
[ -z "$entry" ] && exit 0

repo=$(sesh list --json | jq -r --arg name "$entry" '[.[] | select(.Name == $name) | .Path][0] // empty') || fail 'Cannot list sesh directories.'
if [ -z "$repo" ] && [ -d "$entry" ]; then
	repo=$entry
fi
if [ -z "$repo" ] || ! cd -- "$repo"; then
	fail "Cannot locate the sesh directory: $entry"
fi
jj root >/dev/null 2>&1 || fail 'Not a jj repository.'

# Popup processes do not reliably inherit TMUX_PANE; capture the session at launch.
parent_target=${SESH_PARENT_SESSION:-${TMUX_PANE:-}}
[ -n "$parent_target" ] || fail 'Cannot identify the parent tmux session.'
parent_session=$(tmux display-message -p -t "$parent_target" '#{session_name}') || fail 'Cannot locate the parent tmux session.'
[ -n "$parent_session" ] || fail 'Cannot locate the parent tmux session.'

choice=$(gum choose 'From main' 'From bookmark…') || exit 0
case "$choice" in
'From main') base=main ;;
'From bookmark…')
	bookmarks=$(jj bookmark list -T 'name ++ "\n"' | sort -u) || fail 'Cannot list jj bookmarks.'
	[ -n "$bookmarks" ] || fail 'No jj bookmarks available.'
	base=$(printf '%s\n' "$bookmarks" | gum filter --header 'Base bookmark') || exit 0
	[ -n "$base" ] || exit 0
	;;
*) exit 0 ;;
esac

name=$(gum input --header "New workspace (base: $base)" --placeholder 'Workspace name') || exit 0
[[ "$name" =~ [^[:space:]] ]] || exit 0

# The global mode is session; this action creates and focuses a window in the parent.
workmux add --base "$base" --mode window --parent-session "$parent_session" -- "$name" || fail 'workmux add failed.'
