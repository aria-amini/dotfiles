# aamini coding

Global rules for Sahand's agents.

## Environment

Main coding sessions run on a lima Ubuntu VM on a MacBook Pro. Sahand connects
over Tailscale SSH, and the Amphetamine app keeps the laptop awake. Clients and
the server share no filesystem.

- Manage home-directory dotfiles with Chezmoi. Edit sources under
  `~/.local/share/chezmoi/home` (`~/dotfiles` links to the repo). Then run
  `chezmoi apply` for the changed targets only.
- Make each URL that a client must load reachable from the client network, not
  server-side localhost. Follow the `tailnet-publish` skill to share a URL or
  file.
- Caddy owns port 443 on the Tailscale IP. Never publish a Tailscale Serve
  mapping on 443.
- For browser work, follow the `browser-use` skill.
- Herdr panes run non-login shells on Linux. Keep `shell_mode = "login"` in
  `~/.config/herdr/config.toml`, so `.zprofile` PATH setup runs.

## Version Control

- Use Git. Preserve uncommitted work before you switch branches or worktrees.
- Use Worktrunk for task worktrees. Run `wt switch --create <branch>` to create
  one. In a non-interactive shell, read the printed path and use it as the
  working directory; `wt` cannot change the parent process directory.
- Review the status and diff before each commit.
- Keep each PR commit clean. To change existing work, amend the commit that owns
  the change: run `git commit --fixup=<sha>`, then
  `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>`. Do not leave fixup
  commits in a PR.
- Rebase, reorder, split, squash, and force-push PR branches without
  permission. Push rewrites with `git push --force-with-lease`.
- Trunk history is immutable: `main`, tags, and other people's branches. Never
  rewrite or force-push it without explicit permission for that exact
  operation. Add a new commit instead.

## Shipping PRs

When a task is complete, ship it without a prompt. Push its branch and open or
update its PR.

### Ship Lanes

Each task uses one lane:

- **full-send**: Merge the PR without a prompt when it is merge-ready.
- **full-review**: After the first push, ask the user for feedback. Ask before
  merge.

Use full-review by default. Use full-send only when the user names it for the
task (for example with "full send" in the prompt). Never select full-send on
your own. Move back to full-review and tell the user if the change grows to
touch auth, secrets, user data, migrations, or production, or if it cannot be
easily reverted.

### One PR for Each Task

Open one PR for each task. A large PR is acceptable. Each PR costs one review,
so do not split a task into more PRs. Split the work into one commit for each
concern. The reviewer reads one commit at a time.

Stack PRs in two cases only. Keep dependencies below consumers.

- Dependent work must continue while the previous PR waits for review or CI.
- Cleanups accumulate in a high-churn PR. Move them to one PR at the bottom of
  the stack and merge it first.

For a stacked PR, branch from the branch below and open the PR with
`gh pr create --base <branch-below>`.

Own each PR until it is merged or merge-ready. Fix failures without a prompt.
Wait on checks with `gh pr checks <pr> --watch`, not chained `sleep` calls.

### Code Review

If the changes are large and need a second pass, run 1 to 3 adversarial reviews
with a subagent. Never run more than 3 reviews; findings degrade into noise
after 3 rounds. CodeRabbit does not count toward this limit.

Request a CodeRabbit review with `@coderabbitai review`. In full-send, request
it after green CI. In full-review, request it after the user gives feedback. Do
not use CodeRabbit autofix. It adds commits outside the commit-per-concern
structure. Fix real findings by hand in the commit that owns them. Reply in each
thread with the fix or the false-positive reason, then resolve it. After each
round of fixes, request another review. Continue until CodeRabbit approves the
PR.

### Clean Up

A PR is merge-ready when CodeRabbit approved it, all checks and deploys are
green, and all threads are resolved. After a stack update, recheck each affected
PR. Merge bottom-up with `gh pr merge <pr> --squash --delete-branch`. Before you
merge the next PR, rebase its branch onto `main`, force-push it, and change its
base with `gh pr edit <pr> --base main`.

After the merge, remove the task worktree as the last action of the task:

1. Run `wt remove <branch>` from outside the worktree. Never remove the main
   checkout.
2. Use the t3 MCP to settle the thread. Do not archive it.

## Style

- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long-term
  maintainability.
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
