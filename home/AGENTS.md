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

- Use jujutsu (jj) for all reads and writes. Never use git for writes.
- Keep each PR commit clean. To change existing work, amend the commit that owns
  the change with `jj squash --into <rev>` or `jj absorb`. Do not append a fixup
  commit.
- Rebase, reorder, split, squash, and force-push PR commits and bookmarks
  without permission. A pushed bookmark does not make a commit immutable.
- Workspace commits are mutable; protect active work through coordination, not
  workspace-based `immutable_heads()` rules. Keep `snapshot.auto-update-stale`
  disabled so stale working copies require explicit reconciliation.
- Before rewriting history shared with another workspace, run `jj workspace
  list` to find affected workspaces (their working copies sit on or above a
  rewritten commit). Run `jj status` in each to snapshot its files. If one is
  already stale, coordinate its reconciliation before continuing. If another
  agent or user is actively editing there, coordinate a pause before rewriting
  or updating its files, even if its working-copy commit is empty. Otherwise,
  proceed without permission when its working-copy commit is empty; ask first
  when it is nonempty. Amend shared commits with `jj squash --into <rev>` or
  `jj absorb`, not `jj edit` in another workspace.
- After a rewrite, explicitly run `jj workspace update-stale` in affected,
  paused or idle workspaces before resuming work there. Never auto-update and
  retry a stale-workspace error blindly; inspect the rewrite first. Editors and
  dev servers can still read stale files until the update.
- Trunk history is immutable: trunk, tags, and untracked remote bookmarks. Never
  rewrite it, bypass it with `--ignore-immutable`, or change `immutable_heads()`
  without explicit permission for that exact operation. Add a new commit instead
  when possible.

## Shipping PRs

When a task is complete, ship it without a prompt. Push its bookmarks and open
or update its PR.

### Ship Lanes

Each task uses one lane:

- **full-send**: Merge the PR without a prompt when it is merge-ready.
- **full-review**: After the first push, ask the user for feedback. Ask before
  merge.

Use full-review by default. Use full-send only when the user names it for the
task (for example with "full send" in the prompt). Never select full-send on
your own. And move back to full-review and tell the user if the change grows to
touch: auth, secrets, user data, migrations, production, or if a change cannot
be easily reverted. Just alert the user if you feel the need to.

### jj-ryu (Stacked PRs)

ryu maps each bookmark in a jj stack to one PR. It sets the base of each PR to
the bookmark below it and registers the GitHub stack. Create one bookmark for
each PR. Track the bookmarks with `ryu track --all`. Publish and update with
`ryu submit`.

Open one PR for each task. A large PR is acceptable. Each PR costs one review,
so do not split a task into more PRs. Split the work into one jj commit for each
concern. The reviewer reads one commit at a time.

Stack PRs in two cases only. Keep dependencies below consumers.

- Dependent work must continue while the previous PR waits for review or CI.
- Cleanups accumulate in a high-churn PR. Move them to one PR at the bottom of
  the stack and merge it first.

Use [the jj-ryu fork](https://github.com/aria-amini/jj-ryu) to submit and merge
PRs. Do not use `gh pr create` or `gh pr merge`. Use `gh` only for checks,
labels, and review comments.

Own each PR until it is merged or merge-ready. Fix failures without a prompt.
Wait on checks with `gh pr checks <pr> --watch`, not chained `sleep` calls.

### Code Review

If the changes are large and need a second pass, run 1 to 3 adversarial reviews
with a subagent. Never run more than 3 reviews, findings degrade into noise
after 3 rounds. CodeRabbit does not count, this is only a limit for local
code-review.

Request a CodeRabbit review with `@coderabbitai review`. In full-send, request
it after green CI. In full-review, request it after the user gives feedback. Do
not use CodeRabbit autofix. It writes git commits that ignore the jj commit
structure. Fix real findings by hand. Reply in each thread with the fix or the
false-positive reason, then resolve it. After each round of fixes, request
another review. CodeRabbit reviews only the new commits. Continue until
CodeRabbit approves the PR.

### Clean Up

A PR is merge-ready when CodeRabbit approved it, all checks and deploys are
green, and all threads are resolved. After a stack update, recheck each affected
PR. Merge bottom-up with `ryu merge --yes <name>`, then run `ryu sync`.

After the merge, remove the task workspace as the last action of the task:

1. Run `jw current` to get the workspace name.
2. Run `cd "$(jw path default)" && jw remove --delete-bookmark <name>`. Never
   remove the default workspace.
3. Use the t3 MCP to settle the thread. archive.
