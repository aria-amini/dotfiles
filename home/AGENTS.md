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
- When you finish, stop the dev servers you started unless the user is still
  using a preview. A merge removes the thread's worktree, so copy out untracked
  files you still need, such as `.env`, first.

## Version Control

- Each task works on its own branch in its own worktree. T3 Code creates one
  per thread, and `wt switch --create <branch>` creates one outside T3.
- Keep one commit per concern. Rewrite freely until a reviewer has seen the PR;
  after that, add fixes as new commits starting with `[review]`.
- No scratch commits (`wip`, `tmp`) or backup branches. Never rewrite or
  force-push the default branch or tags.
- PRs squash-merge, so the PR title becomes the commit on `main`. Match the
  repo's recent titles.
- Before review, rebase onto the default branch. After review, merge it in.

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

Shipping is opt-in. When asked to file, babysit, full stop, or full send a PR,
use the `pr` skill. For a second opinion, use `review-loop` or `council`.
