# Dotfiles

Personal machine setup managed with chezmoi and mise.

## Bootstrap

All bootstrap and setup scripts live under `home/.chezmoiscripts/`.
The bootstraps install chezmoi, then apply the dotfiles and OS setup scripts.

macOS and Linux:

```bash
curl -fsSL --retry 3 https://raw.githubusercontent.com/aria-amini/dotfiles/main/home/.chezmoiscripts/run_bootstrap.sh -o bootstrap-dotfiles.sh && bash bootstrap-dotfiles.sh
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/aria-amini/dotfiles/main/home/.chezmoiscripts/run_bootstrap.ps1 | iex
```

The bootstraps use chezmoi's embedded Git client, so a fresh machine does not need system Git first.
Windows installs chezmoi through WinGet, then applies SSH, WezTerm, and OpenCode config files.
After the first install, run `chezmoi apply` for later changes.

## Structure

```text
home/.chezmoiscripts/
  run_bootstrap.sh
  run_bootstrap.ps1
  run_onchange_after_setup-linux.sh.tmpl
  run_onchange_after_setup-darwin.sh.tmpl
  run_onchange_after_setup-windows.ps1.tmpl
```

Run `run_bootstrap.sh` directly on macOS or Linux. Run `run_bootstrap.ps1` directly on Windows.
Chezmoi requires the `run_` prefix inside `.chezmoiscripts/`.
The bootstrap scripts are excluded through `.chezmoiignore`, so chezmoi never executes them.
Each OS has one automatic setup script. Linux setup includes the workspace tools and optional services.
The scripts run after dotfile updates, so tools can use their managed config files.
`run_onchange_` runs setup on the first apply and when the rendered script changes.
Linux and macOS scripts include the Mise config hash, so tool-list changes also trigger setup.
Chezmoi executes these scripts without creating a `.chezmoiscripts` directory in the destination.

## Options

Pass options after the bootstrap command:

```bash
bash bootstrap-dotfiles.sh --profile core
```

Run the installer with `--help` to list options.

The Unix bootstrap supports these options. Profiles select Linux setup.

| Option | Behavior |
| --- | --- |
| `--profile core` | Install base packages, bootstrap tools, dotfiles, Nix, and the login shell |
| `--profile full` | Also install managed tools, workspace tools, and optional services; this is the default |
| `--yes` | Use defaults without prompts; defer authentication and T3 Code confirmation |
| `--dry-run` | Preview the bootstrap and apply command without an install |
| `--source DIR` | Apply an existing dotfiles source without a clone or reset |

Gum handles interactive output. Non-interactive runs print command output directly.
Linux setup saves a transcript and reports its path on failure.
Existing source checkouts stay intact. The installer does not fetch or reset them.
Relative source paths resolve from the directory where you start the installer.
Unattended chezmoi conflicts stop the install without a prompt or an overwrite.
Run `chezmoi diff` and resolve the conflict before you repeat the install.
The installer downloads each upstream script completely before execution.
Bootstrap tools use explicit Mise versions without changes to your global config.
Privileged commands use sudo for non-root users and run directly for root.
The bootstrap exports `DOTFILES_PROFILE` for Linux setup. Bare `chezmoi apply` uses the full profile by default.
For a core apply, run `DOTFILES_PROFILE=core chezmoi apply`.

## CI and pull requests

CI runs on pushes and pull requests:

| Check | Coverage |
| --- | --- |
| `check` | ShellCheck, rendered Bash script syntax, JSON syntax, and workflow checks |

The main ruleset requires pull requests, the `check` job, resolved review threads, and linear history.
It blocks direct pushes, branch deletion, and force pushes. Merges use squash only.
Like the TanStack template, the ruleset requires zero approvals and has no bypass actors.

GitHub settings live in `.github/repo-settings.json` and `.github/rulesets/main.json`.
Apply these files with repository admin access:

```bash
bash .github/scripts/sync-github-settings.sh
```
