#!/usr/bin/env bash

action=${1:-}

case "$action" in
add)
	printf 'Branch: '
	read -r branch
	[ -z "$branch" ] && exit 0
	args=(add "$branch")
	;;
add-from-branch)
	if ! jj root >/dev/null 2>&1; then
		echo "Not a jj repository"
		echo "Press any key to close."
		read -n 1 -s
		exit 1
	fi

	selection=$(jj bookmark list -T 'name ++ "\n"' | grep -v '@' | fzf)
	[ -z "$selection" ] && exit 0
	args=(add "$selection")
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
	printf 'Usage: %s {add|add-from-branch|add-prompt|open|remove|close}\n' "$0" >&2
	exit 2
	;;
esac

workmux "${args[@]}" || {
	echo
	echo "workmux ${args[0]} failed. Press any key to close."
	read -n 1 -s
}
