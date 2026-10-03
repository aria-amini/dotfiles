# Dotfiles

Personal machine setup managed with chezmoi and mise.

## Bootstrap

Run the installer for your OS. The wrapper detects the OS and runs
`install-linux.sh` or `install-mac.sh`.

macOS and Linux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/install.sh)
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/aria-amini/dotfiles/main/install-windows.ps1 | iex
```

## Options

Pass installer options after the wrapper command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/install.sh) --minimal
```

Run the installer with `--help` to list options.
