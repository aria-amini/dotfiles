"""Popup wizard: name a new jj workspace, create it, open it in herdr.

Creation never runs start hooks in the popup: the herdr workspace opens
and focuses immediately, and the hooks run in its left pane instead, so a
slow or failing setup neither blocks the UI nor prevents the switch.
"""

import argparse
import os
import re
import sys
from collections.abc import Callable, Mapping
from pathlib import Path

from .lib.jj import JjError, Workspace, add_workspace, primary_root
from . import state
from .open import open_workspace
from .reporter import ensure
from .state import resolve_context

_WORKSPACE_NAME = re.compile(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*")


class CreateError(RuntimeError):
    pass


def workspace_root(env: Mapping[str, str]) -> Path:
    override = env.get("JJ_WORKSPACE_ROOT")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".herdr" / "workspaces"


def create_workspace(name: str, cwd: Path, env: Mapping[str, str]) -> Workspace:
    if not _WORKSPACE_NAME.fullmatch(name) or any(
        part in (".", "..") for part in name.split("/")
    ):
        raise CreateError(
            "workspace name must contain only letters, digits, '.', '_', '-', and "
            "safe '/' separators"
        )
    primary = primary_root(cwd)
    root = workspace_root(env) / primary.name / name
    if root.exists():
        raise CreateError(f"destination {root} already exists")
    root.parent.mkdir(parents=True, exist_ok=True)
    add_workspace(root, name, cwd=cwd, revision="@")
    return Workspace(name=name, root=root)


def wizard(
    env: Mapping[str, str] | None = None,
    input_fn: Callable[[str], str] = input,
) -> int:
    env = os.environ if env is None else env
    cwd = Path(resolve_context(env)["cwd"])

    try:
        primary = primary_root(cwd)
    except JjError as error:
        print(f"herdr-jj wizard: {error}", file=sys.stderr)
        return 1

    name = input_fn("workspace name: ").strip()
    if not name:
        print("herdr-jj wizard: empty workspace name", file=sys.stderr)
        return 1

    try:
        created = create_workspace(name, cwd, env)
    except (JjError, CreateError) as error:
        print(f"herdr-jj wizard: {error}", file=sys.stderr)
        return 1

    rc = open_workspace(created.root, primary, created.name)
    if rc == 0:
        ensure(env)
    return rc


def add_parser(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser("wizard", help="create a new jj workspace (popup)")
    parser.set_defaults(run=run)


def run(args: argparse.Namespace) -> int:
    return wizard()
