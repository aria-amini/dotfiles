# aamini coding

Global rules for Aria's agents.

## Environment

Sessions run on a lima Ubuntu VM (arm64). Clients reach it over Tailscale and
share no filesystem with it.

- Manage home-directory dotfiles with Chezmoi. Edit the sources in your task's
  checkout of the dotfiles repo, never the deployed targets. Then apply only
  the changed targets: `chezmoi apply --source <checkout>/home <target>...`.
  Targets exclude `run_` scripts; after changing one, run
  `chezmoi apply --source <checkout>/home --include scripts`.
- Make each URL that a client must load reachable from the client network, not
  server-side localhost. Follow the `tailnet-publish` skill to share a URL or
  file.
- The VM has limited memory. Run heavy checks one at a time.

## Version Control

- Each task works on its own branch in its own worktree. T3 Code creates one
  per thread, and `wt switch --create <branch>` creates one outside T3.
- Before review starts, keep each PR commit clean: one commit per concern.
  Amend, reorder, and force-push (`--force-with-lease`) freely until then.
- Once a reviewer has seen a PR, do not rewrite its commits. Add each round of
  review fixes as new commits whose message starts with `[review]`, for example
  `[review] Handle an empty shelf in the finder`.
- Do not create scratch commits (`wip`, `tmp`) or backup branches.
- Never rewrite the default branch or tags, and never force-push them.

## Shipping PRs

When a task is complete, ship it without a prompt: push its branch and open its
PR with `gh pr create --title <title> --body-file <file>`, or update it with
`gh pr edit`.

### Ship Lanes

Each task uses one lane:

- **full-send**: Merge the PR without a prompt when it is merge-ready.
- **full-stop**: After the first push, ask the user for feedback. Ask before
  merge.

Use full-stop by default. Use full-send only when the user names it for the
task (for example with "full send" in the prompt). Never select full-send on
your own. Move back to full-stop and tell the user if the change grows to
touch auth, secrets, user data, migrations, or production, or cannot be easily
reverted.

### One PR per task

Default to a single PR for each task. A large PR is acceptable; the reviewer
reads one commit at a time. Stack PRs only when the user asks, and build the
stack with `gh stack` (`init`, `add`, `submit --auto`, `sync`,
`merge --yes --squash`).

Own each PR until it is merged or merge-ready. Fix failures without a prompt.
If a tool fails because of your branch or repo state, fix that and rerun. If
GitHub or the tool itself fails, stop and report the error.

Never wait with `sleep` loops. In T3 Code, use `watch_pull_request` for checks
and reviews and `schedule_task` for a timed retry. Outside T3, use
`gh pr checks <pr> --watch --fail-fast`, then, even if the watch failed, read
the PR's new review comments and check results before you reply. Tell the user
what you are waiting on.

### Code Review

If the changes are large and need a second pass, run 1 to 3 adversarial reviews
with a subagent. CodeRabbit does not count toward this limit.

Request a CodeRabbit review with `@coderabbitai review`: in full-send after
green CI, in full-stop after the user gives feedback. Defer it when the task
says so, but never merge to the default branch without its approval unless the
user says to skip it for that PR. Do not use CodeRabbit autofix. Fix real
findings in `[review]` commits, reply in each thread with the fix or the
false-positive reason, resolve it, and request another review. Continue until
CodeRabbit approves.

A round is done when CodeRabbit submits a review on the current head commit
after your request, or its summary reports no actionable comments for that
head. A thread reply is not a review. When it is rate limited, find its newest
comment that states a wait ("available in N minutes"), either its reply or its
summary, add N to that comment's `updated_at`, and retry once at that time. Do
not post probe comments.

### Merge and clean up

A PR is merge-ready when CodeRabbit approved its head commit, all checks and
deploys are green, and no review thread is unresolved. Merge with
`gh pr merge --squash --delete-branch`, or `gh stack merge --yes --squash` for
a stack. Close any PR your task superseded, with a comment linking its
replacement.

When you finish, stop the dev servers you started, unless the user is still
using a preview. T3 Code removes a thread's worktree after its PR merges; the
user runs `mise run repo-prune` to clear other merged worktrees and branches
(it skips any under a day old, so recent ones go on a later run).
Copy out any untracked or ignored files you still need, such as `.env` files,
before the merge.
