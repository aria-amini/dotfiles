"""Keybound actions (no TTY): stash context and open the popup panes."""

import argparse
import os
import sys
from collections.abc import Mapping
from pathlib import Path

from .lib.herdr import herdr
from .lib.jj import JjError, primary_root
from . import state
from .reporter import ensure
from .state import resolve_context

PLUGIN_ID = "aamini.jj"


def _open_pane(pane: str, env: Mapping[str, str]) -> int:
    cwd = Path(resolve_context(env)["cwd"])
    try:
        primary_root(cwd)
    except JjError as error:
        print(f"herdr-jj: {error}", file=sys.stderr)
        return 1
    state.write_context(env, {"cwd": str(cwd)})
    herdr("plugin", "pane", "open", "--plugin", PLUGIN_ID, "--entrypoint", pane)
    ensure(env)
    return 0


def pick(env: Mapping[str, str] | None = None) -> int:
    env = os.environ if env is None else env
    return _open_pane("picker", env)


def add_parser(subparsers: argparse._SubParsersAction) -> None:
    subparsers.add_parser("pick", help="open the workspace picker popup").set_defaults(
        run=lambda args: pick()
    )
