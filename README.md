# Dotfiles

Personal machine setup managed with chezmoi and mise.

Bootstrap a fresh machine with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aria-amini/dotfiles/main/install.sh)
```

## Layout

| Path                               | What it is                                       |
| ---------------------------------- | ------------------------------------------------ |
| `home/`                            | chezmoi source state for `$HOME`                 |
| `home/dot_config/mise/config.toml` | machine-wide toolchains and global tasks         |

Standalone tools live in their own repositories (`~/tools/*`, `~/templates/*`)
and reach PATH through mise and uv. Everything else in `.local/bin` is invoked
by other programs (git difftools).

## Commands

Run from the repo root:

```bash
mise run apply                    # update $HOME from the source state
```

List everything with `mise tasks --all`.

Create the managed Lima instance configuration with:

```bash
limactl create --name default ~/.config/lima/default.yaml -y
```
