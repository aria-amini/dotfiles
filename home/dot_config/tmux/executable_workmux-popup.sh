#!/usr/bin/env bash

action=${1:-}

if [ "$action" = add-from-sesh ]; then
	entry=${2:-}
	[ -z "$entry" ] && exit 0

	if [ -d "$entry" ]; then
		repo=$entry
	else
		repo=$(sesh list --json | jq -r --arg name "$entry" '[.[] | select(.Name == $name) | .Path][0] // empty')
	fi
	if [ -z "$repo" ] || ! cd "$repo"; then
		printf 'Cannot locate the sesh directory: %s\nPress any key to close.\n' "$entry" >&2
		read -r -n 1 -s
		exit 1
	fi

	choice=$(tv --source-command "printf 'add from main\\nadd from branch\\n'" --no-preview --no-remote) || exit 0
	case "$choice" in
	'add from main') action=add-from-main ;;
	'add from branch') action=add-from-branch ;;
	*) exit 0 ;;
	esac
fi

case "$action" in
add-from-main)
	printf 'New workspace name: '
	read -r name
	[ -z "$name" ] && exit 0
	args=(add "$name" --base main)
	;;
add-from-branch)
	if ! jj root >/dev/null 2>&1; then
		printf 'Not a jj repository. Press any key to close.\n' >&2
		read -r -n 1 -s
		exit 1
	fi

	selection=$(tv --source-command "jj bookmark list -T 'name ++ \"\\n\"'" --no-preview --no-remote) || exit 0
	[ -z "$selection" ] && exit 0
	printf 'New workspace name (base: %s): ' "$selection"
	read -r name
	[ -z "$name" ] && exit 0
	args=(add "$name" --base "$selection")
	;;
add-prompt)
	printf 'Prompt: '
	read -r prompt
	[ -z "$prompt" ] && exit 0
	args=(add -A -p "$prompt")
	;;
open | remove | close)
	selection=$(workmux list | tail -n +2 | fzf)
	[ -z "$selection" ] && exit 0
	branch=$(awk '{print $1}' <<<"$selection")
	args=("$action" "$branch")
	;;
*)
	printf 'Usage: %s {add-from-main|add-from-branch|add-from-sesh|add-prompt|open|remove|close}\n' "$0" >&2
	exit 2
	;;
esac

workmux "${args[@]}" || {
	echo
	echo "workmux ${args[0]} failed. Press any key to close."
	read -r -n 1 -s
}
