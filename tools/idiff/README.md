# idiff

Terminal image review for jj repositories. Renders image changes in a revision
with the Kitty, iTerm2, Sixel, or ANSI half-block protocol.

Forked from [imgap](https://github.com/roblillack/imgap) at commit
`af3d1a9c6923a73ce216055241151c8c0009d620` (upstream main, snapshot import;
see the history root). The protocol renderers, palette, and comparison modes
are upstream code; the CLI (usage-rs), jj integration, and tmux passthrough
are new. MIT licensed; see `LICENSE`.

## Usage

```bash
idiff                  # image changes in @
idiff -r <rev>         # image changes in another revision
idiff completions zsh
```

Repo mode works from any directory inside a jj workspace. Added and deleted
files render the missing side as white and open as a single image. Keys:

- `[` / `]` — previous / next changed file
- `f` — toggle the changed-file list (`j`/`k` move, `Enter` opens)
- `m` — cycle comparison modes (2-up, swipe, onion skin, difference)
- `s` — flip sides, `←` / `→` — move the swipe/onion slider (`Shift` = 5x)
- `q` / `Esc` — quit

## Renderers

| Protocol | Where it works |
| --- | --- |
| Kitty | Ghostty / kitty directly, or any client inside tmux via DCS passthrough |
| iTerm2 | iTerm2 / WezTerm directly (outside tmux) |
| Sixel | Terminals and tmux >= 3.4 reporting Sixel in DA1 |
| ANSI | Fallback everywhere: colored half-blocks, no image protocol needed |

Inside tmux, kitty images are wrapped in `ESC Ptmux;` passthrough (requires
`allow-passthrough on`, default in recent tmux) and capability is detected
from tmux's own `client_termtype`, since tmux cannot relay protocol probes.
Override any of this with `--renderer` or `IDIFF_RENDERER`.

## Development

```bash
mise run install   # cargo build --release + symlink into ~/.local/bin
mise run check     # fmt + clippy + test
```
