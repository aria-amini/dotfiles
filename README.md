# Dotfiles

Personal machine setup managed with chezmoi and mise.

Bootstrap a fresh machine with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/install.sh)
```

## Pull requests

Direct pushes to `main` are blocked. Work on a bookmark and merge through a PR.

1. Create a bookmark on your work: `jj bookmark create <name> -r @`.
2. Push it: `jj git push --bookmark <name>`.
3. Open a PR. The `check` and `chezmoi` jobs must pass. Squash-merge only.
4. Sync after merge: `jj git fetch`.

Repo settings and rulesets are code: `.github/repo-settings.json` and
`.github/rulesets/`. Apply changes with
`.github/scripts/sync-github-settings.sh`.
