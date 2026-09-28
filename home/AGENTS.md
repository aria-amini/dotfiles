# aamini coding

This document outlines global rules for Aria's agents to follow.

## Remote Development

My main coding sessions are done on my lima Ubuntu VM running on my macbook pro.
I ssh into the laptop using tailscale and have the laptop set to stay awake
using the amphetamine app.

### Dotfiles

Manage home-directory dotfiles with Chezmoi. Edit their source files in
`~/dotfiles/home`, then apply only the changed targets with `chezmoi apply`.

### Notes

- Browser automation connects from the server to a browser on a client over CDP,
  or falls back to a headless browser on the server.
- URLs that a client must load stay reachable from the client network (Tailscale
  or published DNS), never server-side localhost. No shared filesystem exists
  between server and clients. When the user must view a file, start a loopback
  server and publish it with
  `tailscale serve --bg --set-path=/<unique-path> <port>`. Read the node DNS
  name with `tailscale status --json`, then hand over the full HTTPS URL.
  Inspect existing Serve mappings first.
- The Pitchfork proxy owns loopback port 443 on this VM, so a local request to
  the default Serve URL can hit the proxy instead of Serve. Pass an explicit
  `--https=<free-port>` to `tailscale serve`. Curl the exact handover URL and
  confirm HTTP 200 before handover; Serve may strip the `--set-path` prefix
  before proxying, so the backend document root decides the final path.
- Do not replace or reset mappings you did not start.
- For T3 Code dev servers, use `vp run dev --share`; do not configure Tailscale
  Serve by hand.

## Herdr jj workspaces

### Setup

Herdr panes run non-login shells on Linux. Keep `shell_mode = "login"` in
`~/.config/herdr/config.toml`, so `.zprofile` PATH setup runs.

### Spin up a workspace

Create a jj-backed herdr workspace `<name>` for `<repo>`. Run all steps
headlessly through the herdr socket CLI.

1. From the repo root, run `jw add <name>`. jj-waltz creates the workspace at
   `<repo>.<name>`, creates the bookmark, and links required files such as
   `.env.local` (see `.jwlinks.toml`), which prevents a varlock secret prompt
   in headless panes.
2. Run
   `herdr worktree open --cwd <repo-root> --path <worktree> --label <name> --no-focus`.
3. Split the root pane right. Run
   `herdr pane run <right-pane> "mise run bootstrap"`.
4. Run `herdr agent start <name> --kind opencode --pane <root-pane>`.
5. Poll `herdr pane read <right-pane> --source recent` for "Bootstrap complete".
   Do not block on long `wait-output` calls.

Create the jj workspace before opening it in herdr. herdr's `worktree create`
makes git-only checkouts that jj cannot adopt.

herdr 0.9.1 names: `pane wait-output` (not `wait output`), `agent start
--kind`, `worktree open --cwd --path`.

### Remove a workspace

1. Close the herdr workspace.
2. Run `jw remove <name>` from the repo root.

### Update a copier project

Run `copier update --trust --defaults`. Copier leaves conflict markers in
files that diverged from the template. Resolve by taking the incoming side for
template-managed files, then re-render a fresh copy of the template into a
temp dir to verify the result. When a project's origin points at the template,
copier checks the template ref out inside the project and jj imports stray
template commits; rebase project history onto the real tip.

## Rules

### Version Control

- **DO NOT USE GIT**. Prefer the jujutsu (jj) version control system.
- Treat commits protected by the local jj `immutable_heads()` revset as shared
  history. Never rewrite, rebase, squash, abandon, or bypass that protection
  without the user's explicit permission for that exact operation. Do not add
  `remote_bookmarks()` to `immutable_heads()`; a remote bookmark alone does not
  make a commit immutable.
- Before an approved immutable-commit operation, identify the affected commits
  and explain the impact. Rewriting can make parallel workspaces stale or
  divergent and discard reviewable history. Prefer a new descendant commit and a
  forward bookmark move when that preserves the intended stack.

### Coding Style

- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long-term
  maintanability.
- Never write comments that restate what the code already says — if a comment
  explains _what_ the code does, delete it and rename or restructure the code
  instead. Comments must add information the code cannot express. Allowed
  - **Critical context** — why a non-obvious decision was made, constraints
    imposed by external systems, or links to reference material.
  - **Section markers** — short labels (often one word) like `// Shared`, or the
    banner style `// ===== Section =====`, to annotate blocks of code.
- Please make plans incredibly terse. I find long plans with too many details
  very difficult to read.
- For Technical text, use ASD-STE100 style. Max 20 words per sentence in
  instructions, 25 in descriptions. Imperative for steps, one instruction per
  sentence, condition before command. Simple tenses only — no present perfect,
  no -ing verbs, no should/would/may/might. Active voice. One word per meaning —
  no synonym rotation. No contractions, keep articles and "that". Delete filler:
  simply, robust, seamlessly, leverage. Code and identifiers stay exact.
