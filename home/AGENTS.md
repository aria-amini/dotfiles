# aamini coding

This document outlines global rules for Aria's agents to follow.

## Remote Development

My main coding sessions are done on my lima Ubuntu VM running on my macbook pro.
I ssh into the laptop using tailscale.

### Dotfiles

Manage home-directory dotfiles with Chezmoi. The source repo lives at
`~/.local/share/chezmoi`; edit source files under `~/.local/share/chezmoi/home`,
then apply only the changed targets with `chezmoi apply`.

### Notes

- Browser automation prefers Chrome on the client over CDP. Detect the online
  client with `tailscale status`. Ask the user to start Chrome with remote
  debugging when no client browser runs. Use the server headless browser only
  when no client is reachable. Use the full Playwright Chromium with
  `--headless=new`; never use `chrome-headless-shell`. Set
  `CHROME_DEVTOOLS_AXI_BROWSER_URL` on every axi call.
- URLs that a client must load stay reachable from the client network (Tailscale
  or published DNS), never server-side localhost. No shared filesystem exists
  between server and clients. When the user must view a file, start a loopback
  server and publish it with
  `tailscale serve --bg --https=8443 --set-path=/<unique-path> <port>`. Read the
  node DNS name with `tailscale status --json`, then hand over the full HTTPS
  URL. Inspect existing Serve mappings first.
- Caddy terminates TLS on the Tailscale IP at port 443 and proxies to the
  Pitchfork proxy on loopback port 9443. Portless URLs are
  `https://<name>.dev.ariaamini.com`. Hostnames are single-level: slugs flatten
  directory dots to hyphens (`app.worktree` serves as `app-worktree`). Nested
  hostnames (`worktree.app.dev…`) and direct `:9443` access do not work: the
  wildcard certificate covers one level, and the proxy binds loopback only.
  Register a worktree with
  `pitchfork proxy add <slug> --daemon dev --dir <workspace-root>`.
- Port ownership on the Tailscale IP: Caddy owns port 443. Ad-hoc Tailscale
  Serve publishes set an explicit `--https` port in the 8443–8499 range, never
  the default 443. Evict a Serve mapping from 443 on sight; never touch mappings
  on other ports without their owner.
- Publish Impeccable decision pages with
  `impeccable-decision serve <payload.json>`. Share the printed tailnet URL.
  Collect the answer with `impeccable-decision wait`. Tear down with
  `impeccable-decision down`. The wrapper handles the engine Host check, the
  serve port, and the page lifetime.
- For T3 Code dev servers, use `vp run dev --share`; do not configure Tailscale
  Serve by hand.

## Herdr jj workspaces

### Setup

Herdr panes run non-login shells on Linux. Keep `shell_mode = "login"` in
`~/.config/herdr/config.toml`, so `.zprofile` PATH setup runs.

### Spin up a workspace

When asked to "spin up a workspace" or to "implement X in a new workspace",
follow this recipe. Derive `<name>` from X as short kebab-case, for example
`auth-rework`. Pass X as the prompt in step 4. With no task, skip step 4. Create
a jj-backed herdr workspace `<name>` for `<repo>`. Run all steps headlessly
through the herdr socket CLI.

1. From the repo root, run `jw add <name>`. jj-waltz creates the workspace at
   `<repo>.<name>`, creates the bookmark, and links required files such as
   `.env.local` (see `.jwlinks.toml`), which prevents a varlock secret prompt in
   headless panes.
2. Run
   `herdr worktree open --cwd <repo-root> --path <worktree> --label <name> --no-focus`.
3. Run `herdr agent start <name> --kind pi --pane <root-pane>`. Pi Herdsman
   loads and marks the pane as a lead. Name the agent after the workspace.
4. Give the lead the task with
   `herdr agent prompt <name> "<task>" --wait --until working --timeout 10000`.
   Delegate subtasks with `agent_delegate` in the lead chat. Children inherit
   the workspace cwd, so each task runs in its own jj workspace.

Create the jj workspace before opening it in herdr. herdr's `worktree create`
makes git-only checkouts that jj cannot adopt.

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

### Stacked PRs

Use stacked diffs by default for dependent changes. Use
[my jj-ryu fork](https://github.com/aria-amini/jj-ryu) as the Graphite equivalent for jj.

- Keep one focused PR per bookmark, with dependencies below consumers and all branches in the same repository.
- Describe each layer with `jj describe -m "<summary>"`.
- Name it with `jj bookmark create <layer> -r @`.
- Start the next layer with `jj new <layer>`.
- Inspect with `ryu`, then track with `ryu track --all`.
- Publish with `ryu submit`; ryu registers the native GitHub stack where available.
- After fixes, update the affected bookmarks with jj, then resubmit with `ryu submit`.
- After review approval, merge bottom-up with `ryu merge <layer>`, then run `ryu sync`.

`ryu merge <layer>` also merges every unmerged layer below it. The immutable-history rules apply to all stack operations.

### Greptile Auto-Fix and Review

Use [Greptile's auto-fix skills](https://www.greptile.com/docs/mcp-v2/skills) on every PR before merge.

- Use `/check-pr <number>` for comments and failed checks; use `/greploop <number>` for up to five review/fix cycles.
- Replace the skills' Git steps with jj and `ryu submit`; use Greptile MCP or `gh` if skills are unavailable.
- Validate findings, test fixes, and explain false positives in review threads.
- Target 5/5 confidence and zero unresolved comments; report blockers at the loop limit.
- Before merge, require latest-diff review, green required checks, resolved threads, and required reviewer approvals for every affected PR.
- Recheck after stack updates; a Greptile score alone does not authorize merge.

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
