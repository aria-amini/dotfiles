import argparse
from pathlib import Path
from unittest.mock import patch

import pytest

from herdr_jj import adopt as adopt_module
from herdr_jj.lib.jj import Workspace

PRIMARY = Path("/repo")
PATH = Path("/wt/feat")
EVENT = {
    "workspace": {"workspace_id": "w1"},
    "worktree": {"path": str(PATH), "branch": "feat"},
}


@pytest.fixture()
def base():
    with (
        patch.object(adopt_module, "_jj_primary", return_value=PRIMARY),
        patch.object(adopt_module, "workspaces", return_value=[]),
        patch.object(adopt_module, "jj") as jj,
    ):
        yield jj


class TestRun:
    def test_unwraps_data_envelope(self, monkeypatch):
        seen = []
        monkeypatch.setenv(
            "HERDR_PLUGIN_EVENT_JSON",
            '{"event": "worktree_created", "data": {"worktree": {"path": "/wt/x"}}}',
        )
        with patch.object(adopt_module, "_jj_primary", return_value=None):
            rc = adopt_module._run(argparse.Namespace(), seen.append)
        assert rc == 0
        assert seen == [{"worktree": {"path": "/wt/x"}}]

    def test_tolerates_missing_event(self, monkeypatch):
        monkeypatch.delenv("HERDR_PLUGIN_EVENT_JSON", raising=False)
        with patch.object(adopt_module, "_jj_primary", return_value=None):
            rc = adopt_module._run(argparse.Namespace(), lambda event: None)
        assert rc == 0


class TestAdopt:
    def test_adopts_with_real_command(self, base):
        adopt_module.adopt(EVENT)
        base.assert_called_once_with("git", "worktree", "adopt", cwd=PATH)

    def test_skips_non_jj_repo(self):
        with (
            patch.object(adopt_module, "_jj_primary", return_value=None),
            patch.object(adopt_module, "jj") as jj,
        ):
            adopt_module.adopt(EVENT)
        jj.assert_not_called()

    def test_skips_existing_workspace(self, base):
        with patch.object(
            adopt_module,
            "workspaces",
            return_value=[Workspace(name="feat", root=PATH)],
        ):
            adopt_module.adopt(EVENT)
        base.assert_not_called()

    def test_aborts_on_missing_path(self, base):
        with pytest.raises(adopt_module.AdoptError):
            adopt_module.adopt({"worktree": {}})


class TestForget:
    def test_forgets_matching_jj_workspace(self, tmp_path):
        (tmp_path / ".jj").mkdir()
        event = {
            "workspace": {
                "workspace_id": "w1",
                "worktree": {"repo_root": str(tmp_path)},
            },
            "worktree": {"path": "/wt/feat"},
        }
        with patch.object(adopt_module, "jj") as jj:
            adopt_module.forget(event)
        jj.assert_called_once_with("workspace", "forget", "feat", cwd=tmp_path)

    def test_skips_without_repo_info(self):
        with patch.object(adopt_module, "jj") as jj:
            adopt_module.forget({"worktree": {"path": "/wt/feat"}})
        jj.assert_not_called()
