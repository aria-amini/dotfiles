# Dotfiles

Personal machine setup managed with chezmoi and mise.

## Bootstrap

Run the bootstrap script for your OS. The shell script detects the OS and runs
`setup/linux.sh` or `setup/darwin.sh`.

macOS and Linux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/bootstrap.sh)
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/aria-amini/dotfiles/main/bootstrap.ps1 | iex
```

## Options

Pass bootstrap options after the command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/bootstrap.sh) --profile core --yes
```

Run `bootstrap.sh --help` to list options.

Linux core installs base packages, bootstrap tools, Nix, dotfiles, and the login shell.
Linux full also installs managed tools and the Herdr jj plugin.
Use `--skip-managed-tools` to skip the managed tool catalog and the plugin during setup.
Select optional services with `--with docker,tailscale,pitchfork,t3` on the full profile.

Full-profile plugin failures stop apply. Correct the failure, then repeat setup or Chezmoi apply to retry.
Direct Linux Chezmoi apply installs the plugin unless `DOTFILES_PROFILE=core` or `DOTFILES_SKIP_MANAGED_TOOLS=true`.
