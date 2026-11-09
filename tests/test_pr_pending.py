import runpy

from conftest import ROOT

pending = runpy.run_path(str(ROOT / "home/dot_local/bin/executable_pr-pending"))[
    "pending"
]


def thread(author: str, resolved: bool = False) -> dict:
    return {
        "isResolved": resolved,
        "path": "a.py",
        "comments": {"nodes": [{"author": {"login": author}, "url": "u"}]},
    }


def test_flags_only_what_still_needs_the_agent() -> None:
    items = pending(
        [thread("coderabbitai"), thread("me"), thread("coderabbitai", resolved=True)],
        "me",
        [
            {"name": "check", "conclusion": "FAILURE"},
            {"name": "lint", "conclusion": "SUCCESS"},
        ],
        2,
    )
    assert items == [
        "unanswered review thread on a.py: u",
        "failing check: check",
        "2 local commit(s) not pushed",
    ]


def test_nothing_pending() -> None:
    assert (
        pending([thread("me")], "me", [{"name": "c", "status": "IN_PROGRESS"}], 0) == []
    )


def test_judges_each_check_by_its_newest_run() -> None:
    checks = [
        {"name": "check", "conclusion": "CANCELLED", "startedAt": "2026-11-09T01:12:04Z"},
        {"name": "check", "conclusion": "SUCCESS", "startedAt": "2026-11-09T01:12:08Z"},
        {"name": "lint", "conclusion": "SUCCESS", "startedAt": "2026-11-09T01:00:00Z"},
        {"name": "lint", "conclusion": "FAILURE", "startedAt": "2026-11-09T01:05:00Z"},
    ]
    assert pending([], "me", checks, 0) == ["failing check: lint"]
