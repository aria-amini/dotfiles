#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash -n install.sh
bash -n test/lint.sh
bash -n test/e2e/inside.sh

if command -v shellcheck > /dev/null 2>&1; then
  shellcheck -S warning install.sh test/lint.sh test/e2e/inside.sh
else
  echo "shellcheck not found; skipping"
fi

if command -v shfmt > /dev/null 2>&1; then
  shfmt -d -i 2 install.sh test/lint.sh test/e2e/inside.sh
else
  echo "shfmt not found; skipping"
fi

if command -v chezmoi > /dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    chezmoi execute-template --source "$PWD" < "$f" > /dev/null || {
      echo "template failed: $f" >&2
      exit 1
    }
  done < <(find home -name '*.tmpl' -not -name '.chezmoi.toml.tmpl' -print0)
  echo "templates ok"
else
  echo "chezmoi not found; skipping template check"
fi

echo "lint ok"
