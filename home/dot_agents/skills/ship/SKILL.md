---
name: ship
description: Take a PR through review to ready ("full stop") or to merged ("full send"). Use when the user says "full stop" (even as a closing "Full stop.") or "full send", or asks to babysit a PR through review.
---

# Ship

Two escalations past `file-pr`. Never pick one on your own.

- **Full stop:** the PR is green and reviewed. Stop at the merge gate and never
  merge, enable auto-merge, or push to the default branch. Turn off any
  auto-merge already on the PR before you start, and tell the user.
- **Full send:** the same, then merge it and do its Cleanup steps that only
  touch this machine, such as `chezmoi apply` (pull the main checkout first,
  then apply the changed targets). Leave the rest, such as
  `copier update` in apps or a platform workflow run, to the user and list
  them in the report.

Babysitting an existing PR is full stop from step 5. There, the proof is the
checks CI runs on the head, plus proof for each fix you push.

The user is not watching. Stay active until the mode ends: if you end your
turn while checks or bots are pending and no watcher will wake you, nobody
will prompt you again. Back off
from full send to full stop, and tell the user, if the change grows to touch
auth, secrets, user data, migrations, or production, or cannot be easily
reverted.

## Steps

1. **Finish** with the smallest change that works. Fix the case that happened,
   not every case that could.
2. **Prove** every change. See "Proof".
3. **Review** large changes with the `review-loop` skill. Settle any item it
   leaves disputed yourself, and list it in the report.
4. **File** with the `file-pr` skill until CI is green. Add one line to the
   description that says how you proved the change.
5. **Get it reviewed.** See "Review".
6. **Full send:** merge at the merge gate, then do the Cleanup steps.
   **Full stop:** stop at the merge gate.
7. **Report** the PR link, the merge commit or final head, your proof, the
   decisions you made for the user, and any step left for them. For full stop,
   say whether it is ready, waiting only on human approval, or blocked and why.

Either request lets you use any test method Proof needs without asking first,
even where a project file says to ask, and force-push the PR's branch with
`--force-with-lease` until a reviewer has seen it. Rules about how to test still
apply, the permission covers only this task's tests, and it never bypasses a
harness approval prompt.

## Proof

Proof is evidence you observed in this session. Use the most direct proof:
reproduce the failure and watch the fix pass it; run the checks CI runs; add
one focused test that fails without the fix when the behavior has none. For UI,
the repo's screenshot tests are the proof: update baselines only for intended
changes, and say which ones changed. If you cannot prove a change, ask.

## Review

If the user said to skip CodeRabbit for this PR, skip this paragraph and wait
with `pr-wait --until green`, then for any other review bot to finish.
Otherwise, request a CodeRabbit review with
`@coderabbitai review` once CI is green, and
again after every push, including a base merge, since its approval must be on
the head. Wait with `file-pr`'s watcher: `watch_pull_request` in T3 (watch
again if you unwatched), `pr-wait --until ready` elsewhere. Never use its
autofix or post probe comments. When it is rate limited, add the "available in
N minutes" wait from its newest comment to that comment's `updated_at` and
retry once then (`schedule_task` in T3 Code, one background command that waits
elsewhere). If it is still rate limited, stop at the gate and report it.

Handle every unresolved thread, whenever it was opened, and checks and
comments newer than the latest push. Verify each finding against the
source. Fix real ones in new `[review]` commits, prove each fix before you
push, and request another review until CodeRabbit approves. Dismiss the rest
with a one-line reason that leads with the conclusion and cites the code or
check. Resolve each thread after your reply posts.

Keep the PR at the size the goal needs. Review loops grow a PR one
cheap-looking fix at a time. Decline unneeded tests, guards for edge cases
that do not matter, extra compatibility, and small performance costs; list them
as follow-ups. Prefer the fix that deletes or narrows code.

Keep up with the base branch: rebase while no reviewer has seen the PR, and
merge the base in after that.

## Merge gate

All true on the latest commit:

- Your proof covers every change in the diff.
- Required checks are green.
- CodeRabbit approved the head, unless the user said to skip it for this PR.
- Other review bots have finished, their findings are fixed or dismissed with
  a reason, and no human review still requests changes.
- The branch is up to date with the default branch and mergeable. A watcher
  wake is news, not a verdict: `watch_pull_request` reports conflicts but not
  BEHIND, so check that yourself.

Right before merging, `git fetch` and check the PR again, and stop the
worktree's services (see "Worktrees" in AGENTS.md). If base commits that
landed after the last green run touch this PR's files, update the branch and
wait for green again. Merge with `gh pr merge --squash` (GitHub deletes the
branch). For a stack, `gh stack merge --yes --squash` merges every PR in it,
so check the gate on each one first, and stop if the stack holds a PR this
task was not asked to merge. Never use `--admin` or other bypasses.

## Asking the user

Ask only when you cannot continue alone: you cannot prove the change, the gate
cannot pass and you cannot fix it, the next step deletes data, touches
production or anything outside the repo beyond the Cleanup steps full send
allows, closes a PR this task did not supersede, or force-pushes another
branch, the goal is ambiguous, or another PR makes this one obsolete. Decide
everything else yourself and list it in the report.

Use the harness's question tool (`AskUserQuestion` in Claude Code,
`request_user_input` in Codex), with the PR link, the blocker, and the options,
recommended first. A question in a normal message goes unseen. If no tool
answers, leave the PR unmerged and open your final message with the question.
