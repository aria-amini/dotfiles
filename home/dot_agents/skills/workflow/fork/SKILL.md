---
name: fork
description: Guidelines for forking a github repo in order to extend custom
functionality.
---

# Fork workflow

Forks use two remotes: `origin` (the fork) and `upstream` (the source repo).
Never push to `upstream`. Local `main` is the fork's source of truth. Mark
durable work with `aamini/*` bookmarks. Push those bookmarks to origin. Sync
from upstream by merge. Never rebase `main` onto upstream.

1. Run `jj git fetch --remote upstream`.
2. Create bookmark `aamini/sync-upstream` at `main`.
3. Run `jj new aamini/sync-upstream main@upstream` to start a merge commit.
4. Resolve conflicts. Build. Run focused tests.
5. Stop. Show the result to the user. Wait for approval.
6. On approval, run `jj bookmark set main -r <merge>` and push `main`.
7. Delete the sync bookmark.

Retire a fork line on an `aamini/archive-*` bookmark. Push the archive first.
Moving `main` backwards or sideways needs user approval first. A tree-wide
format commit stays out of merges. During a merge, resolve format-only files to
upstream. After `main` moves, re-run the formatter as a fresh tip. Do not put
feature commits on top of a format tip.
