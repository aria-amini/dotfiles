from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


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
