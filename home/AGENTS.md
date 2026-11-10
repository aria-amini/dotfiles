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
