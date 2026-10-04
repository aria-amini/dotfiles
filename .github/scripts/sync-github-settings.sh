#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
repo="${1:-aria-amini/dotfiles}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  printf 'Usage: %s [owner/repo]\n' "$0" >&2
  exit 2
}
jq empty "$root/.github/repo-settings.json" "$root"/.github/rulesets/*.json

gh api --method PATCH "repos/$repo" --input "$root/.github/repo-settings.json" --silent
printf 'Synced repository settings: %s\n' "$repo"

for ruleset in "$root"/.github/rulesets/*.json; do
  name="$(jq -er '.name' "$ruleset")"
  id="$(gh api --paginate "repos/$repo/rulesets" | jq -sr --arg name "$name" '
    add | map(select(.name == $name)) |
    if length > 1 then error("duplicate ruleset names") else .[0].id // empty end
  ')"
  if [[ -n "$id" ]]; then
    gh api --method PUT "repos/$repo/rulesets/$id" --input "$ruleset" --silent
  else
    gh api --method POST "repos/$repo/rulesets" --input "$ruleset" --silent
  fi
  printf 'Synced ruleset: %s\n' "$name"
done
