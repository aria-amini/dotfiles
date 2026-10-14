---
name: ship-pr
description:
  'Publish, update, review, and merge jj pull requests and PR stacks with ryu
  (jj-ryu). Covers bookmarks, ryu submit, CodeRabbit review requests, review
  fixes, and the merge checklist. Read this before opening or merging a PR.'
user-invocable: false
---

# ship-pr

Use [the jj-ryu fork](https://github.com/aria-amini/jj-ryu) as the Graphite
equivalent for jj. The immutable-history rules in AGENTS.md apply to all stack
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

## CodeRabbit review

Request a review only for large PRs or PRs that change auth, data, migrations,
or infrastructure. Review settings live in the CodeRabbit dashboard, not in
repo files.

1. Comment `@coderabbitai review` on the PR.
2. Read each CodeRabbit comment. Validate the finding and test the fix.
3. Explain false positives in the review thread.

## Fix

1. Update the affected bookmarks with jj.
2. Resubmit with `ryu submit`.
3. If the PR meets the review criteria, request a new CodeRabbit review.

## Merge

Before merge, check every affected PR:

- Required checks are green.
- All review threads are resolved.
- If CodeRabbit reviewed the PR, CodeRabbit reviewed the latest diff.

Recheck after stack updates. A passing check alone does not authorize merge.

After review approval, merge bottom-up with `ryu merge <name>`, then run
`ryu sync`. `ryu merge <name>` also merges every unmerged PR below it.
