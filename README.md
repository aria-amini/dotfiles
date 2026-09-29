# Dotfiles

Personal machine setup managed with chezmoi and mise.

Bootstrap a fresh machine with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/install.sh)
```

Installer options:

```bash
--verbose          plain output, full transcript to a log file
--non-interactive  never prompt; defer anything needing input
--dry-run          print actions without running them
--minimal          skip docker, tailscale, pitchfork, t3
--skip PHASE       skip one phase (repeatable)
--source DIR       use DIR as the dotfiles source without cloning
```

## Development

```bash
mise run lint        # bash -n, shellcheck, shfmt, chezmoi template compile
mise run e2e-quick   # fresh ubuntu container, toolchain-less install, asserts
mise run e2e-full    # fresh ubuntu container, full install, asserts
```

E2E runs the real installer as a non-root user in `ubuntu:24.04` and asserts
the toolchain resolves in a fresh login shell.
