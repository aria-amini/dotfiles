# aamini coding

Global rules for Aria's agents.

## Environment

Main coding sessions run on a lima Ubuntu VM on a MacBook Pro. Aria connects
over Tailscale SSH. Clients and the server share no filesystem.

- Manage home-directory dotfiles with Chezmoi. Edit sources under
  `~/.local/share/chezmoi/home`. Then run `chezmoi apply` for the changed
  targets only.
- Make each URL that a client must load reachable from the client network, not
  server-side localhost. Follow the `tailnet-publish` skill to share a URL or
  file.
- Caddy owns port 443 on the Tailscale IP. Never publish a Tailscale Serve
  mapping on 443.
- For browser work, follow the `browser-use` skill.

## Version Control

- Use jujutsu (jj). **Never use git** for writes. Read-only git commands, for
  example `git log` or `git show`, are allowed. Never stage, commit, or push
  with git.
- Treat commits protected by the local jj `immutable_heads()` revset as shared
  history. Never rewrite, rebase, squash, abandon, or bypass that protection
  without the user's explicit permission for that exact operation. Do not add
  `remote_bookmarks()` to `immutable_heads()`; a remote bookmark alone does not
  make a commit immutable.
- Before an approved immutable-commit operation, identify the affected commits
  and explain the impact. Rewriting can make parallel workspaces stale or
  divergent and discard reviewable history. Prefer a new descendant commit and a
  forward bookmark move when that preserves the intended stack.

## Pull Requests

Open one PR for each task. A large PR is acceptable. Each PR uses one review
from a limited review quota. Do not split a task into more PRs to make each PR
smaller. Split the work into one jj commit for each concern instead. The
reviewer reads the PR one commit at a time.

When a task is complete, push its bookmarks and open or update its PR. Do not
ask for permission first. Ask before you push to the default branch or merge.

Stack PRs in two cases only:

- Dependent work must continue while the previous PR waits for review or CI.
- The main PR has a lot of churn, and cleanups or small unrelated fixes
  accumulate in it. These changes are ready to merge now. Move them to one PR at
  the bottom of the stack. Merge it first while the rest iterates.

Do not stack PRs for other reasons.

Request a CodeRabbit review only for large PRs or PRs that change auth, data,
migrations, or infrastructure. CodeRabbit reviews are expensive.

Use `ryu` to create, update, and merge PRs. Do not use `gh pr create` or
`gh pr merge`. ryu sets the PR base for each stack layer and registers the
GitHub stack. Use `gh` only for operations that ryu does not support, for
example checks, labels, and review comments.

To publish, review, or merge a PR, follow the `ship-pr` skill.

Own each PR until it is merge-ready. After you push, do not end the task. Watch
every check, deploy status, and requested review until they settle. Fix failures
and review findings without a prompt from the user. Tell the user when the PR is
merge-ready or when you are blocked. The `ship-pr` skill defines each step.

## Code

- When you make technical decisions, give little weight to development cost.
  Prefer quality, simplicity, robustness, scalability, and long-term
  maintainability.
- Never write comments that restate what the code says. Rename or restructure
  the code instead. Allowed comments:
  - **Critical context**: why a non-obvious decision was made, constraints from
    external systems, or links to reference material.
  - **Section markers**: short labels like `// Shared`, or the banner style
    `// ===== Section =====`.

## Writing

- Keep plans terse. Long plans are difficult to read.
- For technical text, use ASD-STE100 style. Max 20 words per sentence in
  instructions, 25 in descriptions. Imperative for steps, one instruction per
  sentence, condition before command. Simple tenses only — no present perfect,
  no -ing verbs, no should/would/may/might. Active voice. One word per meaning —
  no synonym rotation. No contractions, keep articles and "that". Delete filler:
  simply, robust, seamlessly, leverage. Code and identifiers stay exact.
