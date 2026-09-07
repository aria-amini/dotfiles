"""Remove the current jj workspace: close herdr side, forget in jj, delete dir."""

import argparse
import os
import shutil
import sys
from collections.abc import Callable, Mapping
from pathlib import Path

from .lib.jj import (
    JjError,
    current_workspace,
    forget_workspace,
    primary_root,
    repo_root,
)
from .close import close_workspace


class RemoveError(RuntimeError):
    pass


def remove_workspace(
    root: Path,
    primary: Path,
    env: Mapping[str, str] | None = None,
    input_fn: Callable[[str], str] = input,
    assume_yes: bool = False,
) -> int:
    root = Path(root)
    primary = Path(primary)

    try:
        target = current_workspace(root)
    except JjError as error:
        print(f"herdr-jj remove: {error}", file=sys.stderr)
        return 1
    if target.root.resolve() == primary.resolve():
        print(
            "herdr-jj remove: refusing to remove the primary workspace", file=sys.stderr
        )
        return 1

    if not assume_yes:
        answer = (
            input_fn(f"remove jj workspace '{target.name}' at {target.root}? [y/N] ")
            .strip()
            .lower()
        )
        if answer not in ("y", "yes"):
            return 1

    try:
        forget_workspace(target.name, cwd=primary)
    except JjError as error:
        print(f"herdr-jj remove: {error}", file=sys.stderr)
        return 1
    shutil.rmtree(root, ignore_errors=True)
    return close_workspace(target.name, root, primary)


def remove_current(
    env: Mapping[str, str] | None = None,
    input_fn: Callable[[str], str] = input,
    assume_yes: bool = False,
) -> int:
    env = os.environ if env is None else env
    cwd = Path.cwd()
    try:
        root = repo_root(cwd)
        primary = primary_root(cwd)
    except JjError as error:
        print(f"herdr-jj remove: {error}", file=sys.stderr)
        return 1
    return remove_workspace(root, primary, env, input_fn, assume_yes)


def add_parser(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser("remove", help="remove the current jj workspace")
    parser.add_argument(
        "--current",
        action="store_true",
        help="remove the workspace containing the current directory",
    )
    parser.add_argument("--yes", action="store_true", help="skip confirmation")
    parser.set_defaults(run=lambda args: remove_current(assume_yes=args.yes))
