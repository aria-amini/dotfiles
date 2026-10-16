import json
import subprocess

import pytest
from conftest import ROOT

HOME_SOURCE = ROOT / "home"
WSL_KERNEL = "5.15.167.4-microsoft-standard-WSL2"
HOSTS = {
    "linux": {"os": "linux", "kernel": {"osrelease": "6.8.0-generic"}},
    "wsl": {"os": "linux", "kernel": {"osrelease": WSL_KERNEL}},
    "mac": {"os": "darwin", "kernel": {}},
}


def render(template: str, host: str) -> str:
    result = subprocess.run(
        [
            "chezmoi",
            "--source",
            str(ROOT),
            "execute-template",
            "--override-data",
            json.dumps({"chezmoi": HOSTS[host]}),
        ],
        input=(HOME_SOURCE / template).read_text(),
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


@pytest.mark.parametrize(
    ("host", "os", "osrelease"),
    [
        ("wsl", "linux", WSL_KERNEL),
        ("linux", "linux", "6.8.0-generic"),
        ("mac", "darwin", ""),
        ("other", "windows", ""),
    ],
)
def test_host_kind(host: str, os: str, osrelease: str) -> None:
    template = (
        '{{ includeTemplate "host-kind" '
        f'(dict "os" "{os}" "osrelease" "{osrelease}") }}}}'
    )
    result = subprocess.run(
        ["chezmoi", "--source", str(ROOT), "execute-template", template],
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout == host


@pytest.mark.parametrize(
    ("host", "ignored"),
    [
        ("linux", {".config/lima": True, ".config/caddy-lab": False}),
        ("wsl", {".config/lima": True, ".config/caddy-lab": True}),
        ("mac", {".config/lima": False, ".config/caddy-lab": True}),
    ],
)
def test_ignore_rules_follow_the_host(host: str, ignored: dict[str, bool]) -> None:
    rules = render(".chezmoiignore", host).split()
    for path, expected in ignored.items():
        assert (path in rules) is expected, f"{host}: {path}"


@pytest.mark.parametrize(("host", "exported"), [("linux", True), ("wsl", False)])
def test_tailscale_ip_only_on_the_vm(host: str, exported: bool) -> None:
    assert ("TAILSCALE_IP" in render("dot_zprofile.tmpl", host)) is exported


@pytest.mark.parametrize(
    ("config", "ignored"), [("", True), ('encryption = "age"\n', False)]
)
def test_credentials_wait_for_age(tmp_path, config: str, ignored: bool) -> None:
    config_file = tmp_path / "chezmoi.toml"
    config_file.write_text(config)
    result = subprocess.run(
        [
            "chezmoi",
            "--config",
            str(config_file),
            "--source",
            str(ROOT),
            "execute-template",
        ],
        input=(HOME_SOURCE / ".chezmoiignore").read_text(),
        capture_output=True,
        text=True,
        check=True,
    )
    assert (".config/personal-secrets" in result.stdout.split()) is ignored
