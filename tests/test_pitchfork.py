import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest
from conftest import ROOT


@pytest.fixture
def pitchfork_env(tmp_path: Path) -> dict[str, str]:
    binary = tmp_path / "bin/pitchfork"
    binary.parent.mkdir()
    binary.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "with open(os.environ['CALLS'], 'a') as file:\n"
        "    file.write(json.dumps(sys.argv[1:]) + '\\n')\n"
    )
    binary.chmod(0o755)
    return {
        **os.environ,
        "PATH": f"{binary.parent}:{os.environ['PATH']}",
        "XDG_CONFIG_HOME": str(tmp_path / "config"),
        "PITCHFORK_STATE_DIR": str(tmp_path / "state"),
        "CALLS": str(tmp_path / "calls.jsonl"),
    }


def run_script(
    name: str, env: dict[str, str], *args: str
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(ROOT / f"home/dot_local/bin/executable_{name}"), *args],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def calls(env: dict[str, str]) -> list[list[str]]:
    path = Path(env["CALLS"])
    return (
        [json.loads(line) for line in path.read_text().splitlines()]
        if path.exists()
        else []
    )


def test_register_preserves_overrides_and_sets_checkout_specific_namespace(
    tmp_path: Path, pitchfork_env: dict[str, str]
) -> None:
    root = tmp_path / "animations"
    root.mkdir()
    local = root / "pitchfork.local.toml"
    local.write_text("[daemons.dev]\nport = 3005\n")
    for _ in range(2):
        result = run_script(
            "pitchfork-register",
            pitchfork_env,
            "portfolio-animations",
            "--dir",
            str(root),
        )
        assert result.returncode == 0, result.stderr
    assert tomllib.loads(local.read_text()) == {
        "namespace": "portfolio-animations",
        "daemons": {"dev": {"port": 3005}},
    }
    assert len(calls(pitchfork_env)) == 2


def test_register_rejects_conflicting_namespace_without_changes(
    tmp_path: Path, pitchfork_env: dict[str, str]
) -> None:
    config = tmp_path / "pitchfork.toml"
    config.write_text('namespace = "custom"\n[daemons.dev]\nrun = "sleep 60"\n')
    result = run_script(
        "pitchfork-register",
        pitchfork_env,
        "portfolio-animations",
        "--dir",
        str(tmp_path),
    )
    assert result.returncode != 0
    assert "declares namespace" in result.stderr
    assert not (tmp_path / "pitchfork.local.toml").exists()
    assert not calls(pitchfork_env)
