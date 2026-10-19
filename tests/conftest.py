import tomllib
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parent.parent


def mise_tools() -> dict[str, Any]:
    tools: dict[str, Any] = {}
    files = [
        ROOT / "mise-global/config.toml",
        *sorted(ROOT.glob("mise-global/conf.d/*.toml")),
    ]
    for file in files:
        tools |= tomllib.loads(file.read_text()).get("tools", {})
    return tools


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption("--e2e", action="store_true", help="Run Docker setup smoke tests")


def pytest_collection_modifyitems(
    config: pytest.Config, items: list[pytest.Item]
) -> None:
    if config.getoption("--e2e"):
        return
    skip = pytest.mark.skip(reason="Use --e2e to run real setup in Docker")
    for item in items:
        if "e2e" in item.keywords:
            item.add_marker(skip)
