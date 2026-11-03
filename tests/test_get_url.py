import os
import subprocess
from pathlib import Path

import pytest
from conftest import ROOT

SCRIPT = ROOT / "home/dot_config/mise/tasks/executable_get-url"
PROXY_URL = "https://app.dev.example.com"


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    """Put a curl on PATH that answers 200 only for the URLs in $UP_URLS."""
    curl = tmp_path / "bin/curl"
    curl.parent.mkdir()
    curl.write_text(
        "#!/usr/bin/env bash\n"
        'url="${*: -1}"\n'
        'case " $UP_URLS " in *" $url "*) printf 200 ;; *) printf 000; exit 7 ;; esac\n'
    )
    curl.chmod(0o755)
    return {**os.environ, "PATH": f"{curl.parent}:{os.environ['PATH']}", "UP_URLS": ""}


def workspace(tmp_path: Path, base_url: str = PROXY_URL, port: int = 4321) -> Path:
    root = tmp_path / "app"
    (root / "src").mkdir(parents=True)
    (root / ".env.workspace.local").write_text(
        f'APP_PORT="{port}"\nBASE_URL="{base_url}"\n'
        'DATABASE_URL="postgres://u:p@localhost:${POSTGRES_PORT}/db"\n'
    )
    return root


def run(
    cwd: Path, env: dict[str, str], no_check: bool = False
) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=cwd,
        env={**env, "usage_no_check": str(no_check).lower()},
        capture_output=True,
        text=True,
        check=False,
    )


def test_prints_only_the_url_on_stdout_when_everything_answers(
    tmp_path: Path, env: dict[str, str]
) -> None:
    env["UP_URLS"] = f"http://127.0.0.1:4321/ {PROXY_URL}"
    result = run(workspace(tmp_path) / "src", env)
    assert result.returncode == 0, result.stderr
    assert result.stdout == f"{PROXY_URL}\n"
    assert result.stderr.count("✓") == 2


def test_no_check_skips_the_probes(tmp_path: Path, env: dict[str, str]) -> None:
    result = run(workspace(tmp_path), env, no_check=True)
    assert result.returncode == 0
    assert result.stdout == f"{PROXY_URL}\n"
    assert result.stderr == ""


def test_dead_daemon_prints_the_url_and_fails_with_a_hint(
    tmp_path: Path, env: dict[str, str]
) -> None:
    result = run(workspace(tmp_path), env)
    assert result.returncode == 1
    assert result.stdout == f"{PROXY_URL}\n"
    assert "pitchfork start dev" in result.stderr


def test_proxy_failure_is_reported_when_the_local_server_is_up(
    tmp_path: Path, env: dict[str, str]
) -> None:
    env["UP_URLS"] = "http://127.0.0.1:4321/"
    result = run(workspace(tmp_path), env)
    assert result.returncode == 1
    assert "caddy-health" in result.stderr


def test_localhost_base_url_is_probed_once(tmp_path: Path, env: dict[str, str]) -> None:
    env["UP_URLS"] = "http://127.0.0.1:4321/"
    result = run(workspace(tmp_path, base_url="http://localhost:4321"), env)
    assert result.returncode == 0, result.stderr
    assert result.stderr.count("✓") == 1


def test_missing_workspace_file_points_at_bootstrap(
    tmp_path: Path, env: dict[str, str]
) -> None:
    result = run(tmp_path, env)
    assert result.returncode == 2
    assert result.stdout == ""
    assert "mise run bootstrap" in result.stderr
