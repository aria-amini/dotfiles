---
name: file-pr
description: Open a PR and get its CI green. Use when the user asks to file, open, or create a PR, or to get one's checks passing.
---

# File PR

The first step past normal iteration: the PR is open, every change is pushed,
and CI is green. Review and merging belong to the `ship` skill.

## Open it

Check whether a PR for this branch already exists. Review the diff against the
base branch (usually `origin/main`) to make sure it matches the goal.

One PR per task. A large PR is fine when its commits split the change into
logical steps, one concern each, because the reviewer reads one commit at a
time. Use stacked PRs (`gh stack`) only when the user asks for them.

PR titles become the squash commit, so follow the repo's title conventions.
Say why the change matters:

> ❌ perf(server): negotiate permessage-deflate on the websocket
>
> ✅ perf(server): cut websocket frame size by 70%+ with gzipping

Open the description with the problem, in the terms of the user's request,
then briefly explain the solution. Do not lead with an inventory of changes.
If the change needs work after it merges, such as `chezmoi apply` targets,
`copier update` in apps, or a platform workflow run, list it under a
`## Cleanup` heading near the end. End with the attribution lines the harness
gives, if any.

Check the title, description, and attachments for secrets and private details.
Open a real PR, not a draft, so review bots run. If `gh pr create` fails on the
GraphQL rate limit, use REST:
`gh api repos/<owner>/<repo>/pulls -f title=... -f head=... -f base=... -F body=@<file>`.

## Get CI green

Fix real CI failures, and tell them apart from infrastructure flakes. Stop when
the required checks pass on the latest push.

Never write your own polling or `sleep` loop. Use one watcher per PR, because
every watcher on a GitHub account shares one rate limit:

- **T3 Code:** call `watch_pull_request` and end your turn; T3 wakes you on
  check results, comments, and conflicts. Only the thread that owns the PR
  watches it; a delegated child never does. Call `unwatch_pull_request` before
  you stop or ask the user anything. "Stopped watching, could not read it"
  usually means the GitHub rate limit is used up: check
  `gh api rate_limit --jq .resources.graphql`, wait for `reset` with one
  background command, then watch again.
- **Elsewhere:** run `~/.agents/skills/file-pr/scripts/pr-wait <pr> --until green`
  (with the Monitor tool in Claude Code, `timeout_ms: 1800000`, re-armed when
  it expires). It prints one
  line per event and exits 0 when the condition is met, 1 when it needs you,
  and 2 on bad input. Start it again after each push. `--until ready` also
  waits for review bots, including CodeRabbit's approval.

When an event needs no action, end your turn without a message. If GraphQL is
used up, read the PR with `gh api repos/<owner>/<repo>/pulls/<n>` and checks
with `gh api repos/<owner>/<repo>/commits/<sha>/check-runs`.
