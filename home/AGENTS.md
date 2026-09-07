# aamini coding

This document outlines global rules for Aria's agents to follow.

## Architecture

Agents run on a Linux devbox. The devbox is a Lima VM with no mount to the
host filesystem. The devbox is the server: the code, dev servers, the
reverse proxy, the private CA, and agent tooling live there. Clients are
any device the user drives — Mac host, PC desktop, phone. The phone is a
primary client. A client never runs the agent's tooling. Browser
automation connects from the server to a browser on a client over CDP, or
falls back to a headless browser on the server. URLs that a client must
load stay reachable from the client network (Tailscale or published DNS),
never server-side localhost. No shared filesystem exists between server
and clients. When the user must view a file, start a loopback server and
publish it with `tailscale serve --bg --set-path=/<unique-path> <port>`.
Read the node DNS name with `tailscale status --json`, then hand over the
full HTTPS URL. Inspect existing Serve mappings first. Do not replace or
reset mappings you did not start. For T3 Code dev servers, use `vp run dev
--share`; do not configure Tailscale Serve by hand. Keep output readable on

## Rules

1. **DO NOT USE GIT**. Prefer the jujutsu (jj) version control system.
2. Manage home-directory dotfiles with Chezmoi. Edit their source files in
   `~/dotfiles/home`, then apply only the changed targets with `chezmoi apply`.
3. When making technical decisions, do not give much weight to development cost.
   Instead, prefer quality, simplicity, robustness, scalability, and long-term
   maintanability.
4. Never write comments that restate what the code already says — if a comment
   explains _what_ the code does, delete it and rename or restructure the code
   instead. Comments must add information the code cannot express. Allowed
   - **Critical context** — why a non-obvious decision was made, constraints
     imposed by external systems, or links to reference material.
   - **Section markers** — short labels (often one word) like `// Shared`, or
     the banner style `// ===== Section =====`, to annotate blocks of code.
5. Please make plans incredibly terse. I find long plans with too many details
   very difficult to read.
6. For Technical text, use ASD-STE100 style. Max 20 words per sentence in
   instructions, 25 in descriptions. Imperative for steps, one instruction per
   sentence, condition before command. Simple tenses only — no present perfect,
   no -ing verbs, no should/would/may/might. Active voice. One word per meaning
   — no synonym rotation. No contractions, keep articles and "that". Delete
   filler: simply, robust, seamlessly, leverage. Code and identifiers stay
   exact.

7. Treat commits protected by the local jj `immutable_heads()` revset as shared
   history. Never rewrite, rebase, squash, abandon, or bypass that protection
   without the user's explicit permission for that exact operation. Do not add
   `remote_bookmarks()` to `immutable_heads()`; a remote bookmark alone does not
   make a commit immutable.
8. Before an approved immutable-commit operation, identify the affected
   commits and explain the impact. Rewriting can make parallel workspaces stale
   or divergent and discard reviewable history. Prefer a new descendant commit
   and a forward bookmark move when that preserves the intended stack.
