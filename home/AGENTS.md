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

- Keep one commit per concern. Rewrite freely until a reviewer has seen the PR;
  after that, add fixes as new commits starting with `[review]`.
- No scratch commits (`wip`, `tmp`) or backup branches. Never rewrite or
  force-push the default branch or tags.
- PRs squash-merge, so the PR title becomes the commit on `main`. Match the
  repo's recent titles.
- Before review, rebase onto the PR's base branch. After review, merge it in.

## Worktrees

Each task works on its own branch in its own worktree. Never work in a main
checkout (`~/apps/<repo>`, `~/.local/share/chezmoi`); it stays on the default
branch.

- **T3 Code** makes one worktree per thread at `~/.t3/worktrees/<repo>/t3-<id>`
  and removes it after the thread's PR merges. Leave those to T3.
- **Outside T3**, `wt switch --create <branch>` makes one under
  `~/.herdr/workspaces/<repo>/` (`wt list` shows its path) and copies ignored files such as `.env`
  into it. Remove it with `wt remove` when its branch has merged or been
  abandoned.

In an app worktree, run `mise run bootstrap` before anything else. It installs
tools and packages, checks the env, starts the worktree's own Docker services
and migrations if the app has a database, starts the pitchfork `dev` daemon,
and checks the app answers. It needs the OpenBao dev token; if it says the
token is missing, tell the user to run `mise run dev-token` in
`aria-amini/infra`. `mise run get-url` prints the worktree's dev URL, which the
user can open over the tailnet.

Clean up what your task leaves behind:

- GitHub deletes a PR's branch when it merges. Close a PR your task
  superseded, with a comment linking its replacement, and delete its branch.
  Ask before closing any other PR.
- If a PR you opened will not merge, because the work was dropped or it
  targets a branch that is gone, tell the user and offer to close it. A merged
  stacked PR whose base was not the default branch never reached it; report
  that too.
- Remove `wt` worktrees and local branches you made once they merge or are
  abandoned. T3 removes its own worktrees.
- Copy out untracked files you still need before a merge removes a worktree.
- `mise run repo-prune` clears merged worktrees, local branches, and orphaned
  dev servers across all repos. It skips dirty or locked work and anything
  under a day old, so run it after a merge or when they pile up.
- When the work is done (just before a full-send merge, or when it is
  dropped), stop the worktree's services before it is removed:
  `pitchfork stop dev`, and `vp run compose:down` if the app has Docker
  services.

Between turns, leave services running for the user's preview. The backups
cover the rest: pitchfork stops a dev server after 30 minutes without traffic
and restarts it on the next request, and the next bootstrap removes the Docker
stacks of deleted worktrees.

## Repos

My apps live in `~/apps`. Two shared repos sit under them:

- `aria-amini/toolkit`: the Copier app templates (`tanstack`, `astro`) and the
  `@aamini/config` package. Start new apps with
  `copier copy --trust https://github.com/aria-amini/toolkit <dir>`. Fix tooling
  that apps share here, then run `copier update --trust` in each app, rather
  than patching one app.
- `aria-amini/infra`: the platform. OpenBao on Railway holds every app's
  secrets, `apps.json` registers apps, and `mise run onboard <app>` gives an
  app its login. Never read or print secret values.
- `aria-amini/dotfiles`: this Chezmoi source.

All three are public. Never commit secrets, tokens, or private details there.

## Workflows

Normal work is iteration: change, show, take the next instruction. Shipping is
opt-in and escalates one step at a time:

1. "file a PR": `file-pr` opens it, pushes every change, and gets CI green.
2. "babysit": `ship`, from its review step, gets it reviewed and ready.
3. "full stop": `ship` also finishes and proves the change, unattended, and
   stops when it is ready to merge.
4. "full send": `ship` then merges it and does its Cleanup steps.

CodeRabbit reviews are rate limited. Outside `ship`, ask before requesting one
the user did not ask for.

For a second opinion, use `review-loop`. Name a model to get another model's
view.
