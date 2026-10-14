---
name: herdr-workspace
description:
  'Spin up a jj-backed herdr workspace with a Pi lead agent. Use when asked to
  "spin up a workspace" or to "implement X in a new workspace".'
user-invocable: false
---

# herdr-workspace

Derive `<name>` from the task X as short kebab-case, for example `auth-rework`.
Run all steps headlessly through the herdr socket CLI. For the CLI reference,
read the `herdr` skill. With no task, skip step 4.

1. From the repo root, run `jw add <name>`. jj-waltz creates the workspace at
   `<repo>.<name>`, creates the bookmark, and links required files such as
   `.env.local` (see `.jwlinks.toml`). The links prevent a varlock secret prompt
   in headless panes.
2. Run
   `herdr worktree open --cwd <repo-root> --path <worktree> --label <name> --no-focus`.
3. Run `herdr agent start <name> --kind pi --pane <root-pane>`. Pi Herdsman
   loads and marks the pane as a lead.
4. Give the lead the task with
   `herdr agent prompt <name> "<task>" --wait --until working --timeout 10000`.
   Delegate subtasks with `agent_delegate` in the lead chat. Children inherit
   the workspace cwd, so each task runs in its own jj workspace.

Create the jj workspace before opening it in herdr. herdr's `worktree create`
makes git-only checkouts that jj cannot adopt.

Herdr panes run non-login shells on Linux. If a pane lacks PATH entries, check
that `~/.config/herdr/config.toml` keeps `shell_mode = "login"`.
