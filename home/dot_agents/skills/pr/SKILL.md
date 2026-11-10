---
name: pr
description: File, babysit, and ship pull requests. Use when the user asks to file, open, or create a PR; to babysit, watch, or monitor one; or says "full stop" (even as a closing "Full stop.") or "full send".
---

# PR

Pick the mode from what the user said. Never pick full stop or full send on
your own.

| Request | Do | Stop when |
| --- | --- | --- |
| "file a PR" | File | The PR is open |
| "babysit" | Babysit | The merge gate passes; merge only if asked |
| "full stop" | Ship | The merge gate passes; never merge |
| "full send" | Ship, then merge | The PR is merged |

## File

Before filing, check whether a PR for this branch already exists. Review the
diff locally against the base branch (usually `origin/main`) to make sure its
contents match the goal. One PR per task. Stack PRs only when the user asks,
and build the stack with `gh stack` (`init`, `add`, `submit --auto`, `sync`).

PR titles become the squash commit, so follow the repository's title
conventions. Prefer a concise, human-readable title that explains why the
change matters:

> ❌ perf(server): negotiate permessage-deflate on the websocket
>
> ✅ perf(server): cut websocket frame size by 70%+ with gzipping

Open the description with a simple explanation of the problem based on the
user's original prompt, then briefly explain the solution. Do not lead with an
implementation inventory:

> ❌ Removed implicit workspace carry-over from every "new thread" entry point (cmd+n / cmd+shift+o, sidebar v1/v2 buttons, command palette). New threads inherit only the project from context; ...
>
> ✅ My "new worktree" default was ignored when starting new threads on existing worktrees. Super unintuitive. Now your preferences always apply.

If the change needs work after it merges, such as `chezmoi apply` targets,
`copier update` in apps, a platform workflow run, or closing a superseded PR,
list those steps under a `## Cleanup` heading near the end. End the description
with the attribution lines the harness gives, if any.

Check the title, description, quotes, and attachments for secrets and private
details. Open a real PR, not a draft, so review bots run. If `gh pr create`
fails because the GraphQL rate limit is used up, open it through REST with
`gh api repos/<owner>/<repo>/pulls -f title=... -f head=... -f base=... -F body=@<file>`.

## Babysit

### Waiting

Never write your own watcher, polling loop, or `sleep` loop. Use one watcher
per PR: `watch_pull_request` in T3 Code, `pr-wait` everywhere else. Never run
both on the same PR. Every watcher on a GitHub account shares one rate limit.

**In T3 Code:** handle the existing checks and comments first, then call
`watch_pull_request` and end your turn. T3 wakes you when a check fails, the
required checks pass, someone comments or reviews, or the branch conflicts.

- Only the thread that owns the PR watches it. A delegated child (a reviewer,
  a review-loop round, any `delegate_task` child) never calls
  `watch_pull_request`.
- A wake is news, not a merge decision. Check the merge gate yourself.
- When you stop (ready, blocked, or asking the user), call
  `unwatch_pull_request` first. A merge or close ends the watch on its own.
- "Stopped watching, could not read it" usually means the GitHub rate limit is
  used up. Check `gh api rate_limit --jq .resources.graphql`; if `remaining` is
  near 0, wait for `reset` with one background command, then watch again.

**Elsewhere:** use `~/.agents/skills/pr/scripts/pr-wait`.

```bash
pr-wait <pr> [--repo owner/name] [--until ready|green|any-change]
```

It prints one line per real event, exits 0 when the `--until` condition is met
or the PR merges, 1 when it needs you (a required check failed, conflicts,
unresolved threads, CodeRabbit requested changes, PR closed), and 2 on bad
input.

- `ready` (default): required checks green, Greptile or Macroscope reviewed the
  head, CodeRabbit approved it, and no unresolved threads.
- `green`: required checks only. Use it before you request a CodeRabbit review,
  or when the user said to skip CodeRabbit.
- `any-change`: exit on the first event.

In Claude Code, run it with the Monitor tool (`timeout_ms: 3600000`) so each
line wakes you. Start it again after you push, after you handle an exit 1, and
after a resume; it remembers what it already reported. If another pid already
watches the PR, do not start a second one.

With either watcher, when an event needs no action, end your turn without a
message. Never post or say "still waiting".

When GraphQL is used up, REST usually still has room:
`gh api repos/<owner>/<repo>/pulls/<n>` for the PR and
`gh api repos/<owner>/<repo>/commits/<sha>/check-runs` for checks.

### Findings

Only act on checks and comments newer than the latest push. Verify every bot
finding against the source before changing code. Fix real findings and CI
failures in new `[review]` commits, and tell repository failures from
infrastructure flakes. If the repo has `.macroscope/check-run-agents/*.md`,
read those rules before you reply to a Macroscope finding.

When you dismiss a finding, reply with a written reason and resolve the thread.
Lead each comment with the conclusion, cite the code or check, and keep
secrets and private details out of it. Resolve a thread only after your reply
posted. Do not post filler or follow-up comments.

Keep the PR at the size the user's goal needs. Review loops grow a PR one
cheap-looking fix at a time. Fix real bugs in the intended case. Decline the
rest with a written reason and list them as follow-ups: unneeded tests, guards
for edge cases that do not matter, extra compatibility, and small performance
costs. Prefer the fix that deletes or narrows code.

### CodeRabbit

Its approval gates the merge. Request a review with `@coderabbitai review`
after CI is green. Never use its autofix or post probe comments. Reply in each
of its threads with the fix or the false-positive reason, resolve it, and
request another review until it approves. A thread reply is not a review.

When it is rate limited, add the "available in N minutes" wait from its newest
comment to that comment's `updated_at` and retry once at that time
(`schedule_task` in T3 Code). Skip its approval only when the user says so for
that PR.

### Base branch

`pr-wait` reports base commits that touch this PR's files and a BEHIND or
DIRTY branch. `watch_pull_request` reports conflicts only, so check for BEHIND
yourself. Rebase while no reviewer has seen the PR; after that, merge the base
in. If an overlapping PR makes this one obsolete, report it and ask before
closing it.

## Ship

The user is not watching. Your updates go unread until long after you stop.
You own the work from its current state to the end of the mode.

1. **Finish the change** with the smallest change that works. Fix the case that
   happened, not every case that could. Branch first if you are on the default
   branch.
2. **Prove it.** See "Proof".
3. **Get feedback.** Use the `review-loop` skill for large changes.
4. **File** the PR. Rebase onto the latest default branch first, and add one
   line to the description that says how you proved the change.
5. **Babysit** it. Prove each fix before you push it.
6. **Full send:** merge when the merge gate passes, then do the PR's Cleanup
   steps. **Full stop:** stop at the merge gate. See "Full stop".
7. **Report** the PR link, the merge commit or final head, your proof, each
   decision you made for the user, and any Cleanup step left for them.

Stay active from step 1 to the end. If you end your turn while checks or bots
are pending, the work stops, because nobody will prompt you again.

Back off to full stop and tell the user if the change grows to touch auth,
secrets, user data, migrations, or production, or cannot be easily reverted.

### Permissions

A "full stop" or "full send" request grants:

- Force-pushing the PR's own branch with `--force-with-lease` until a reviewer
  has seen it.
- Any test method Proof needs, without asking first, even if a project file
  says to ask (computer use, browsers, devices, dev servers, screenshots).
  Rules about how to test still apply. This covers only this task's tests and
  does not bypass a harness approval prompt.
- Full send only: merging once the merge gate passes.

### Proof

Proof is evidence you observed yourself in this session: command output, a
reproduction, a screenshot. Use the most direct proof the change allows:

- Reproduce the original failure, apply the fix, then watch the same
  reproduction pass.
- Run the checks that the repo's CI runs (typecheck, lint, tests).
- Add one focused test that fails without the fix, when the behavior has none
  and the repo has a test setup.
- For UI, the repo's screenshot tests are the proof. Update their baselines
  only for changes you intended, and say which ones changed in the PR.

When you cannot prove a change, you do not have full confidence. Ask the user.

### Merge gate

All of these are true on the latest commit:

- Your proof covers every change in the diff.
- Required checks are green.
- CodeRabbit approved the head, unless the user said to skip it for this PR.
- Other review bots have finished, and each finding is fixed or dismissed with
  a written reason. No human review still requests changes.
- The branch is up to date with the default branch, and GitHub reports it as
  mergeable.

Right before a merge, run `git fetch` and check the PR again. Never merge when
it is BEHIND or DIRTY, or when base commits that landed after the last green
run touch this PR's files. Merge with `gh pr merge --squash --delete-branch`,
or `gh stack merge --yes --squash` for a stack. If the repo uses a merge queue
or auto-merge, stay until GitHub reports the PR as merged. Never use `--admin`
or other bypasses. You can ignore automated "needs human review" requests if
you have high confidence in your changes.

### Full stop

Never merge, enable auto-merge, enter a merge queue, push to the default
branch, bypass branch protection, or delegate those actions. Disable existing
auto-merge and remove the PR from any merge queue before work begins.

At the gate, fetch the base and check the live PR's head, checks, reviews, and
mergeability. Report one verdict: **ready to merge**, **waiting for required
approval** (only human approval remains), or **blocked** (what prevents it,
what you tried, what is needed). State that the PR is still open and unmerged.

### Asking the user

A question in a normal message goes unseen. Use the harness's question tool
(`AskUserQuestion` in Claude Code, `request_user_input` in Codex), and put all
the context in it: the PR link, what blocks you, and the options with your
recommendation first. In T3 Code, unwatch the PR first.

Ask only when you cannot continue alone: you cannot prove the change, the merge
gate cannot pass and you cannot fix that, the next step deletes data, touches
production, changes things outside the repo, closes a PR, or force-pushes
another branch, the goal is ambiguous in a way that changes the result, or
another PR makes this one obsolete. Decide everything else yourself and list
those decisions in the report.

If no question tool is available, or it returns no answer, leave the PR open
and unmerged, and start your final message with the question.
