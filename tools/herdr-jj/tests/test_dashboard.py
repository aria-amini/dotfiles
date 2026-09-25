import asyncio
from contextlib import nullcontext
from dataclasses import replace
from pathlib import Path

from textual.widgets import DataTable, Input

from herdr_jj.dashboard import Dashboard, Dialog
from herdr_jj.dashboard_data import AHEAD, PR_ICON, Agent, Row, Snapshot


def test_group_navigation_current_selection_and_refresh():
    async def exercise():
        rows = [
            Row(Path("/a/z"), Path("/a"), "z", ahead=1),
            Row(Path("/b/a"), Path("/b"), "a", ahead=1, current=True),
            Row(Path("/b/b"), Path("/b"), "b", ahead=1),
        ]
        app = Dashboard(loader=lambda _: Snapshot(rows))
        async with app.run_test() as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            assert app.selected.key == "/b/a"
            await pilot.press("k")
            assert app.selected.key == "/a/z"
            await pilot.press("down")
            assert app.selected.key == "/b/a"
            await pilot.press("j")
            assert app.selected.key == "/b/b"
            app.snapshot.rows = [
                replace(row, last_commit_ts=999) for row in reversed(rows)
            ]
            app.render_rows()
            await pilot.pause()
            assert app.selected.key == "/b/b"
            await pilot.press("up", "up")
            assert app.selected.key == "/a/z"

    asyncio.run(exercise())


def test_hunk_uses_selected_stack_and_returns_to_selection(monkeypatch):
    from herdr_jj import dashboard

    calls = []
    monkeypatch.setattr(dashboard, "trunk_bookmark", lambda _: "main")
    monkeypatch.setattr(
        dashboard,
        "single",
        lambda _, rev: {
            'bookmarks(exact:"main")': "trunk",
            '"feature"@': "tip",
            "fork_point(trunk | tip)": "base",
        }[rev],
    )
    monkeypatch.setattr(
        dashboard.subprocess,
        "run",
        lambda args, **kwargs: (
            calls.append((args, kwargs))
            or dashboard.subprocess.CompletedProcess(args, 0)
        ),
    )

    async def exercise():
        row = Row(Path("/repo/feature"), Path("/repo"), "feature", ahead=2)
        app = Dashboard(loader=lambda _: Snapshot([row]))
        monkeypatch.setattr(app, "suspend", nullcontext)
        async with app.run_test() as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            await pilot.press("d")
            await app.workers.wait_for_complete()
            assert app.selected == row
            assert not app.busy
        assert calls == [
            (["hunk", "diff", "base", "tip"], {"cwd": Path("/repo"), "check": False})
        ]

    asyncio.run(exercise())


def test_bookmark_cell_shows_relationship_inline():
    async def exercise():
        rows = [
            Row(
                Path("/repo/wt"),
                Path("/repo"),
                "wt",
                bookmark="wt",
                bookmark_state=f"{AHEAD}2",
                ahead=1,
                pr="#7",
                pr_state="OPEN",
            ),
            Row(Path("/repo/bare"), Path("/repo"), "bare", ahead=1),
        ]
        app = Dashboard(loader=lambda _: Snapshot(rows))
        async with app.run_test() as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            table = app.query_one(DataTable)
            assert str(table.get_row_at(1)[3]) == "no bookmark"
            assert str(table.get_row_at(1)[4]) == "—"
            await pilot.press("j")
            assert str(table.get_row_at(2)[3]) == f"wt · {AHEAD}2"
            assert str(table.get_row_at(2)[4]) == f"{PR_ICON} #7"

    asyncio.run(exercise())


def test_filter_bar_only_visible_while_active():
    async def exercise():
        rows = [Row(Path("/repo/a"), Path("/repo"), "a", ahead=1)]
        app = Dashboard(loader=lambda _: Snapshot(rows))
        async with app.run_test() as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            box = app.query_one("#search")
            assert box.has_class("hidden")
            await pilot.press("slash")
            await pilot.pause()
            assert not box.has_class("hidden")
            assert app.focused is box
            box.value = "a"
            await pilot.pause()
            assert len(app.displayed_rows) == 1
            await pilot.press("escape")
            await pilot.pause()
            assert box.has_class("hidden")
            assert box.value == ""
            assert app.focused is not box
            assert len(app.displayed_rows) == 1

    asyncio.run(exercise())


def test_search_opens_parked_result_with_one_enter(monkeypatch):
    from herdr_jj import dashboard

    calls = []
    monkeypatch.setattr(dashboard, "live_state", lambda: ([], []))
    monkeypatch.setattr(
        dashboard, "command", lambda *args, **kwargs: calls.append(args)
    )

    async def exercise():
        row = Row(Path("/repo/parked"), Path("/repo"), "parked", bookmark="release")
        app = Dashboard(loader=lambda _: Snapshot([row]))
        async with app.run_test() as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            assert app.selected is None
            await pilot.press("question_mark")
            await pilot.pause()
            assert isinstance(app.screen, Dialog)
            await pilot.press("escape", "slash")
            app.query_one(Input).value = "release"
            await pilot.pause()
            assert app.selected == row
            await pilot.press("enter")
            await pilot.pause()
        assert calls == [
            ("herdr-jj", "open", "/repo/parked", "--project-path", "/repo")
        ]

    asyncio.run(exercise())


def test_herdr_bin_prefers_injected_server_binary(monkeypatch):
    from herdr_jj.lib import herdr as herdr_module

    monkeypatch.setenv("HERDR_BIN_PATH", "/opt/herdr/current")
    assert herdr_module.herdr_bin() == "/opt/herdr/current"
    monkeypatch.delenv("HERDR_BIN_PATH")
    assert herdr_module.herdr_bin() == "herdr"


def test_live_table_filter_preserves_selection_and_literal_names():
    async def exercise():
        rows = [
            Row(Path("/repo/a"), Path("/repo"), "[red]a", ahead=2),
            Row(
                Path("/other/b"),
                Path("/other"),
                "b",
                agents=(
                    Agent("p1", "t1", "w1", "opencode", "working"),
                    Agent("p2", "t2", "w1", "claude", "blocked"),
                ),
            ),
            Row(None, Path("/repo"), "missing", flags="missing"),
        ]
        app = Dashboard(loader=lambda _: Snapshot(list(rows)), show_all=True)
        async with app.run_test(size=(120, 35)) as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            assert len(app.displayed_rows) == 3
            assert app.selected.name == "b"
            await pilot.press("j")
            assert app.selected.name == "[red]a"
            await pilot.press("k")
            assert app.selected.name == "b"
            app.snapshot.rows.reverse()
            app.render_rows()
            assert app.selected.name == "b"
            await pilot.press("slash")
            app.query_one(Input).value = "blocked"
            await pilot.pause()
            assert [r.name for r in app.displayed_rows] == ["b"]
            await pilot.press("escape", "e")
            await pilot.pause()
            assert isinstance(app.screen, Dialog)
            assert "opencode" in app.screen.body
            assert "claude" in app.screen.body
            await pilot.press("escape")
            assert app.selected.name == "b"

    asyncio.run(exercise())


def test_empty_dashboard_and_small_terminal():
    async def exercise():
        app = Dashboard(loader=lambda _: Snapshot())
        async with app.run_test(size=(60, 18)) as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            await pilot.press("enter", "M", "R", "d", "e", "n")
            await pilot.pause()
            assert app.selected is None

    asyncio.run(exercise())


def test_row_visibility_naming_and_sorting():
    repo = Path("/code/jj")
    working = Row(
        repo,
        repo,
        "default",
        is_primary=True,
        agents=(Agent("p1", "t1", "w1", "opencode", "working"),),
        dirty=True,
    )
    shell = Row(Path("/code/jj/wt"), repo, "wt", sessions=("w9",), last_commit_ts=200)
    dirty = Row(
        Path("/code/other/wt"),
        Path("/code/other"),
        "feat",
        dirty=True,
        last_commit_ts=300,
    )
    ahead = Row(
        Path("/code/third/wt"), Path("/code/third"), "old", ahead=3, last_commit_ts=100
    )
    clean_primary = Row(
        Path("/code/clean"), Path("/code/clean"), "default", is_primary=True, ahead=0
    )
    conflict = Row(Path("/code/x/wt"), Path("/code/x"), "hot", flags="conflict")
    missing = Row(None, Path("/code/y"), "gone", flags="missing")

    assert working.display == "jj"
    assert shell.display == "jj/wt"
    assert clean_primary.active is False
    assert conflict.active is True
    assert missing.active is False
    assert [
        r.display
        for r in sorted(
            [working, shell, dirty, ahead, clean_primary], key=lambda r: r.sort_key
        )
    ] == ["jj", "jj/wt", "other/feat", "third/old", "clean"]

    async def exercise():
        rows = [clean_primary, ahead, missing, working, shell, conflict, dirty]
        app = Dashboard(loader=lambda _: Snapshot(list(rows)))
        async with app.run_test(size=(120, 35)) as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            assert [r.display for r in app.displayed_rows] == [
                "jj",
                "jj/wt",
                "other/feat",
                "third/old",
                "x/hot",
            ]
            await pilot.press("a")
            await pilot.pause()
            assert [r.display for r in app.displayed_rows] == [
                "clean",
                "jj",
                "jj/wt",
                "other/feat",
                "third/old",
                "x/hot",
                "y/gone",
            ]

    asyncio.run(exercise())


def test_grouped_layout_indents_children_and_promotes_qualifiers():
    dotfiles = Path("/code/dotfiles")
    imdbgraph = Path("/code/imdbgraph")
    jjrepo = Path("/code/jj")
    rows = [
        Row(
            Path("/code/jj"),
            jjrepo,
            "default",
            is_primary=True,
            ahead=4,
            last_commit_ts=100,
        ),
        Row(
            Path("/code/dotfiles"),
            dotfiles,
            "default",
            is_primary=True,
            agents=(Agent("p1", "t1", "w1", "opencode", "working"),),
        ),
        Row(
            Path("/code/imdbgraph/wt"),
            imdbgraph,
            "wt",
            sessions=("w9",),
            last_commit_ts=50,
        ),
        Row(
            Path("/code/imdbgraph/setup"),
            imdbgraph,
            "setup",
            agents=(Agent("p2", "t2", "w2", "opencode", "working"),),
            last_commit_ts=60,
        ),
        Row(Path("/code/lonely/wt"), Path("/code/lonely"), "lonely", ahead=1),
    ]
    app = Dashboard(loader=lambda _: Snapshot(rows))
    app.displayed_rows = sorted(rows, key=lambda r: r.sort_key)

    app.grouped = False
    assert [(depth, name) for _, depth, name in app.layout()] == [
        (0, "imdbgraph/setup"),
        (0, "dotfiles"),
        (0, "imdbgraph/wt"),
        (0, "jj"),
        (0, "lonely/lonely"),
    ]

    app.grouped = True
    assert [(depth, name) for _, depth, name in app.layout()] == [
        (1, "default"),
        (1, "setup"),
        (1, "wt"),
        (1, "default"),
        (1, "lonely"),
    ]


def test_diff_viewer_hunk_navigation():
    from herdr_jj.dashboard import DiffViewer

    diff_text = (
        "diff --git a/x b/x\n"
        "index 000..111 100644\n"
        "--- a/x\n"
        "+++ b/x\n"
        "@@ -1,3 +1,3 @@\n"
        " a\n"
        "-b\n"
        "+c\n"
        " d\n"
        "@@ -10,2 +10,3 @@\n"
        "+new\n"
        " e\n"
        " f\n"
    )

    async def exercise():
        app = Dashboard(loader=lambda _: Snapshot())
        async with app.run_test(size=(120, 35)) as pilot:
            app.push_screen(DiffViewer("stack diff · test", diff_text))
            await pilot.pause()
            viewer = app.screen
            assert isinstance(viewer, DiffViewer)
            assert viewer.hunk_lines == [4, 9]
            await pilot.press("n")
            assert viewer.hunk_index == 1
            await pilot.press("n", "n")
            assert viewer.hunk_index == 1
            await pilot.press("p", "p")
            assert viewer.hunk_index == 0
            await pilot.press("q")
            await pilot.pause()
            assert not isinstance(app.screen, DiffViewer)

    asyncio.run(exercise())


def test_group_toggle_persists_preference(monkeypatch, tmp_path):
    monkeypatch.setenv("HERDR_PLUGIN_STATE_DIR", str(tmp_path / "state"))
    app = Dashboard(loader=lambda _: Snapshot())
    app.grouped = True
    app._save_view_preference()
    fresh = Dashboard(loader=lambda _: Snapshot())
    fresh._load_view_preference()
    assert fresh.grouped is True


def test_enter_focuses_fresh_session_handle(monkeypatch):
    from herdr_jj import dashboard

    calls = []
    monkeypatch.setattr(
        dashboard,
        "live_state",
        lambda: (
            [{"workspace_id": "fresh", "worktree": {"checkout_path": "/repo/a"}}],
            [],
        ),
    )
    monkeypatch.setattr(dashboard, "command", lambda *args, **kw: calls.append(args))

    async def exercise():
        row = Row(Path("/repo/a"), Path("/repo"), "a", sessions=("old",))
        app = Dashboard(loader=lambda _: Snapshot([row]))
        async with app.run_test() as pilot:
            await pilot.pause()
            await app.workers.wait_for_complete()
            await pilot.press("enter")
            await pilot.pause()
        assert calls == [("herdr", "workspace", "focus", "fresh")]

    asyncio.run(exercise())


def test_merge_cancel_and_partial_cleanup_result(monkeypatch):
    from herdr_jj import dashboard
    from herdr_jj.finish import MergePlan

    row = Row(Path("/repo/a"), Path("/repo"), "a", sessions=("w1",))
    plan = MergePlan(
        row.root,
        row.repo,
        "a",
        "main",
        "a" * 40,
        "b" * 40,
        "b" * 40,
        ("b" * 40,),
        False,
    )
    calls = []
    monkeypatch.setattr(dashboard.finish, "plan_merge", lambda _: plan)
    monkeypatch.setattr(
        dashboard.finish, "merge", lambda _: calls.append("merge") or "Merged"
    )

    def fail(_):
        raise dashboard.DashboardError("jw refused")

    monkeypatch.setattr(dashboard.finish, "cleanup", fail)

    async def exercise():
        app = Dashboard(loader=lambda _: Snapshot([row]))
        async with app.run_test(size=(120, 35)) as pilot:
            await pilot.pause()
            await pilot.press("M")
            await pilot.pause()
            assert isinstance(app.screen, Dialog)
            await pilot.press("escape")
            assert not calls
            await pilot.press("M")
            await pilot.pause()
            await pilot.click("#finish")
            await pilot.pause()
            assert calls == ["merge"]
            assert "Merged" in app.screen.body
            assert "Cleanup pending: jw refused" in app.screen.body

    asyncio.run(exercise())
