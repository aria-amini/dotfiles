# Dotfiles

Personal machine setup managed with chezmoi and mise.

Bootstrap a fresh machine with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/install.sh)
```

## Layout

| Path | What it is |
| --- | --- |
| `home/` | chezmoi source state for `$HOME` |
| `tools/` | one directory per CLI capability (`dev`, `jj-ws`, `imgview`) |
| `apps/tanstack` | copier template scaffolded by `new-tanstack-app` |
| `home/dot_config/mise/config.toml` | machine-wide toolchains and global tasks |

Chezmoi templates detect macOS, WSL, and Lima guests during initialization.
The WSL apply script manages `/etc/wsl.conf`, `/etc/hosts`, and Windows `.wslconfig`.
The Lima template renders to `~/.config/lima/default.yaml` on macOS.

Tools reach PATH two ways: python CLIs as editable uv tools, and chezmoi-managed
launchers in `home/dot_local/bin` (such as `pix`, which wraps television and
imgap). Everything else in `.local/bin` is invoked by other programs (git
difftools).

## Commands

Run from the repo root:

```bash
mise run check                    # lint + test every tool
mise run install                  # install personal tools onto PATH
mise run apply                    # update $HOME from the source state
```

Global (works from any directory):

```bash
mise run new-tanstack-app <dir>   # scaffold a new TanStack Start app
```

List everything with `mise tasks --all`.

Create the managed Lima instance configuration with:

```bash
limactl create --name default ~/.config/lima/default.yaml -y
```
