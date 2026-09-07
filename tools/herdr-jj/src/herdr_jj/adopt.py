"""Adopt herdr-created git worktrees as jj workspaces.

On worktree.created the fresh git worktree is registered with
`jj git worktree adopt`, preserving the checkout and its branch. On
worktree.removed the matching jj workspace is forgotten.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

from .lib.jj import JjError, jj, workspaces


class AdoptError(RuntimeError):
    pass


def _git(repo_or_path: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_or_path), *args],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise AdoptError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def _jj_primary(path: Path) -> Path | None:
    try:
        common = _git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    except AdoptError:
        return None
    primary = Path(common).parent
    return primary if (primary / ".jj").is_dir() else None


def _event_worktree(event: dict) -> dict:
    return event.get("worktree") or {}


def adopt(event: dict) -> None:
    worktree = _event_worktree(event)
    raw_path = worktree.get("path") or worktree.get("checkout_path")
    if not raw_path:
        raise AdoptError(f"worktree.created event has no path: {event}")
    path = Path(raw_path)
    primary = _jj_primary(path)
    if primary is None:
        print("herdr-jj adopt: not a jj-colocated repo, leaving as git worktree")
        return

    name = path.name
    if any(item.name == name for item in workspaces(primary)):
        print(f"herdr-jj adopt: '{name}' is already a jj workspace")
        return

    jj("git", "worktree", "adopt", cwd=path)


def forget(event: dict) -> None:
    worktree = _event_worktree(event)
    raw_path = worktree.get("path") or worktree.get("checkout_path")
    if not raw_path:
        return
    repo_root = worktree.get("repo_root") or (
        (event.get("workspace") or {}).get("worktree") or {}
    ).get("repo_root")
    if not repo_root or not (Path(repo_root) / ".jj").is_dir():
        return
    name = Path(raw_path).name
    try:
        jj("workspace", "forget", name, cwd=Path(repo_root))
    except JjError as error:
        print(f"herdr-jj forget: {error}", file=sys.stderr)


def _run(args: argparse.Namespace, handler) -> int:
    raw = os.environ.get("HERDR_PLUGIN_EVENT_JSON", "")
    try:
        event = json.loads(raw) if raw else {}
    except json.JSONDecodeError as error:
        print(f"herdr-jj adopt: invalid event JSON: {error}", file=sys.stderr)
        return 1
    try:
        handler(event.get("data", event))
    except (AdoptError, JjError) as error:
        print(f"herdr-jj adopt: {error}", file=sys.stderr)
        return 1
    return 0


def add_parser(subparsers: argparse._SubParsersAction) -> None:
    adopt_parser = subparsers.add_parser(
        "adopt", help="convert a herdr-created git worktree into a jj workspace"
    )
    adopt_parser.set_defaults(run=lambda args: _run(args, adopt))
    forget_parser = subparsers.add_parser(
        "adopt-forget", help="forget the jj workspace for a removed herdr worktree"
    )
    forget_parser.set_defaults(run=lambda args: _run(args, forget))
