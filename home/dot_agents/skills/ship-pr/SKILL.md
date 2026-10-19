---
name: ship-pr
description:
  'Publish, update, review, and merge jj pull requests and PR stacks with ryu
  (jj-ryu). Covers bookmarks, ryu submit, CodeRabbit review requests, CI and
  deploy checks, review fixes, status reports, and the merge checklist. Read
  this before opening or merging a PR.'
user-invocable: false
---

# ship-pr

Use [the jj-ryu fork](https://github.com/aria-amini/jj-ryu) as the Graphite
equivalent for jj. The Version Control rules in AGENTS.md apply to all stack
operations.

## Publish

- Keep dependencies below consumers. Keep all branches in the same repository.
- Describe each commit with `jj describe -m "<summary>"`.
- Name each PR bookmark with `jj bookmark create <name> -r @`.
- Start dependent work with `jj new <name>`.
- Inspect with `ryu`, then track with `ryu track --all`.
- Write the PR body with the `pr` skill.
- Publish with `ryu submit`. ryu registers the native GitHub stack where
  available.

## Watch

After each `ryu submit`, watch the PR until it is merge-ready. Do not end the
task after the first CI run.

- Watch every signal: GitHub Actions, deploy statuses (for example the Railway
  preview), and the CodeRabbit review when you requested it.
- Read all statuses with `gh pr checks <pr>`. A deploy status counts the same as
  a CI check.
- Wait with `gh pr checks <pr> --watch` or a background `until` loop. Do not
  chain `sleep` calls. The harness blocks them.
- To watch for new review comments, use a `Monitor` poll loop on the GitHub API.
  Emit one line for each terminal state, including failures.
- If a check fails, read its log, find the cause, and fix it.
- If you cannot read a log, report it at once. For example, `railway` is not
  logged in. Name the exact access that you need. Do not guess the cause.

## Local review

Run this before any CodeRabbit review. The Review rules in AGENTS.md apply.

1. Ask the user for feedback on the change. Apply it before cleanup.
2. Start a cheap adversarial review with a subagent or the `code-review` skill.
3. Check that each commit matches its description and that the stack is in sync.
4. Spot test the change. Run the affected tests and the changed behavior.
5. Fix real findings in the commit that owns the change. Repeat only while
   findings remain. Stop after 3 rounds of review and fix.

## CodeRabbit review

CodeRabbit reviews are expensive. Request one review, as the last step before
merge, only for large PRs or PRs that change auth, data, migrations, or
infrastructure. Review settings live in the CodeRabbit dashboard, not in repo
files. Request the review yourself when the local review settles.

1. Comment `@coderabbitai review` on the PR.
2. Watch for the review to finish.
3. Read each CodeRabbit comment. Validate the finding and test the fix.
4. Fix real findings by hand in the commit that owns the change. Use
   `jj squash --into <rev> <paths>`. Do not use the CodeRabbit autofix. It
   writes git commits that ignore the jj commit structure.
5. Reply in each thread with the fix, or with the reason for a false positive.
   Resolve the thread.
6. Resubmit. Request a new review only if the 3-round limit allows it and a
   fix changed the PR in a way that needs a new review.

Copier template files, for example `mise-tasks/`, are overwritten on
`copier update`. Do not fix findings on these files in the app PR. Reply in the
thread and offer the user an issue in the template repository.

## Fix

1. Amend the commit that owns each fix with `jj squash --into <rev>` or
   `jj absorb`. Do not append a commit to a PR that already covers the concern.
2. Resubmit with `ryu submit`. ryu force-pushes the rewritten bookmarks.
3. Watch the PR again.

## Report

Tell the user the result. Send a `PushNotification` in these cases only:

- The PR is merge-ready.
- You need a decision from the user.
- You need credentials or access.
- Two fix attempts for the same failure did not work.

Do not send progress notifications. Lead each message with the action that the
user must take, for example `PR #20 merge-ready` or `blocked: railway login`.

## Merge

A PR is merge-ready when all of these are true:

- All checks are green, including deploy statuses.
- All review threads are resolved.
- If CodeRabbit reviewed the PR, each finding is fixed or answered.

Check every affected PR before merge.

Recheck after stack updates. A passing check alone does not authorize merge.

After review approval, merge bottom-up with `ryu merge <name>`, then run
`ryu sync`. `ryu merge <name>` also merges every unmerged PR below it.
