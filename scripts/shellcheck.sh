#!/usr/bin/env bash
# Run shellcheck on every shell script in the repository, found by its shebang so that new scripts
# are covered without editing a list. Chezmoi source names (executable_*, *.tmpl) have no .sh suffix.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

files=()
while IFS= read -r -d '' file; do
  if head -n 1 "$file" | grep -Eq '^#!.*[[:space:]/](ba)?sh([[:space:]]|$)'; then
    files+=("$file")
  fi
done < <(find . \( -name .git -o -name .jj -o -name .venv -o -name node_modules \) -prune -o -type f -print0)

shellcheck -x "${files[@]}"
