import json
import os
import re
import shlex
import shutil
import subprocess
import tomllib
from pathlib import Path

import pytest
from conftest import ROOT
from test_setup import Shell
from test_setup import linux as linux


@pytest.fixture(scope="module")
def chezmoi_binary() -> str:
    binary = shutil.which("chezmoi")
    assert binary is not None, "Install the test dependency with: mise install chezmoi"
    return binary


@pytest.fixture
def modifier(tmp_path: Path, chezmoi_binary: str) -> tuple[list[str], Path]:
    source = tmp_path / "source"
    template = source / "dot_config/pitchfork/modify_config.toml"
    template.parent.mkdir(parents=True)
    shutil.copyfile(ROOT / "home/dot_config/pitchfork/modify_config.toml", template)
    target = tmp_path / "home/.config/pitchfork/config.toml"
    target.parent.mkdir(parents=True)
    config = tmp_path / "chezmoi.toml"
    config.write_text("")
    command = [
        chezmoi_binary,
        "--config",
        str(config),
        "--source",
        str(source),
        "--destination",
        str(tmp_path / "home"),
        "--persistent-state",
        str(tmp_path / "state.boltdb"),
        "--force",
        "apply",
        str(target),
    ]
    return command, target


@pytest.mark.parametrize(
    "config",
    [
        "",
        'namespace = "global"\n[daemons.other]\nrun = "keep"\n'
        '[slugs]\napp = {dir = "/app", daemon = "dev"}\n',
        '[daemons.tls]\nrun = "old"\n[daemons.tls.ready_cmd]\nrun = "old-check"\n'
        '[daemons.tls.health_cmd]\nrun = "old-health"\n',
    ],
)
def test_tls_modifier_preserves_other_configuration(
    config: str, modifier: tuple[list[str], Path]
) -> None:
    command, target = modifier

    def apply(value: str) -> str:
        target.write_text(value)
        subprocess.run(command, text=True, capture_output=True, check=True)
        return target.read_text()

    before = tomllib.loads(config)
    rendered = apply(config)
    after = tomllib.loads(rendered)
    assert after["daemons"].pop("tls")["retry"] is True
    if "daemons" in before:
        before["daemons"].pop("tls", None)
    else:
        before["daemons"] = {}
    assert after == before
    assert apply(rendered) == rendered


def test_tls_modifier_rejects_invalid_input_without_output(
    modifier: tuple[list[str], Path],
) -> None:
    command, target = modifier
    invalid = '[daemons.tls]\nrun = "unterminated'
    target.write_text(invalid)
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    assert result.returncode != 0
    assert result.stdout == ""
    assert target.read_text() == invalid


@pytest.mark.parametrize("available", [True, False])
def test_agent_resolves_mise_from_path(
    tmp_path: Path, chezmoi_binary: str, available: bool
) -> None:
    system_bin = tmp_path / "system bin"
    system_bin.mkdir()
    mise = system_bin / "mise"
    if available:
        mise.write_text("#!/bin/sh\nexit 0\n")
        mise.chmod(0o755)
    template = (ROOT / "home/dot_config/openbao/caddy-agent.hcl.tmpl").read_text()
    config = tmp_path / "chezmoi.toml"
    config.write_text("")
    result = subprocess.run(
        [chezmoi_binary, "--config", str(config), "execute-template"],
        input=template,
        env={**os.environ, "PATH": str(system_bin)},
        text=True,
        capture_output=True,
        check=False,
    )
    if not available:
        assert result.returncode != 0
        assert "Mise must be on PATH" in result.stderr
        return
    assert result.returncode == 0, result.stderr
    match = re.search(r"command = (\[.*\])", result.stdout)
    assert match is not None
    assert json.loads(match[1])[0] == str(mise)


def test_caddy_start_uses_live_address_and_excludes_cli_tokens(linux: Shell) -> None:
    result = linux(r"""
mkdir -p "$HOME/.config/openbao" "$HOME/bin"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'bao "$@"' > "$HOME/bin/bao"
chmod +x "$HOME/bin/bao"
export PATH="$HOME/bin:$PATH"
printf role > "$HOME/.config/openbao/caddy-role-id"
printf secret > "$HOME/.config/openbao/caddy-secret-id"
export CF_API_TOKEN=old BAO_TOKEN=human VAULT_TOKEN=human
mise() { [[ $MISE_AUTO_INSTALL == false && "$*" == 'which caddy-cf' ]]; }
tailscale() { printf '100.64.0.2\n'; }
ip() { printf '    inet 100.64.0.2/32 scope global tailscale0\n'; }
bao() {
  [[ $CADDY_BIND == 100.64.0.2 ]]
  [[ ! -v CF_API_TOKEN && ! -v BAO_TOKEN && ! -v VAULT_TOKEN ]]
  [[ "$*" == "agent -config=$HOME/.config/openbao/caddy-agent.hcl -log-format=json" ]]
}
export -f mise tailscale ip bao
bash "$DOTFILES_DIR/home/dot_local/bin/executable_caddy-start"
""")
    assert result.returncode == 0, result.stdout + result.stderr


def test_caddy_start_requires_enrollment(linux: Shell) -> None:
    result = linux('bash "$DOTFILES_DIR/home/dot_local/bin/executable_caddy-start"')
    assert result.returncode != 0
    assert "OpenBao credential caddy-role-id is unavailable" in result.stderr


def test_pitchfork_setup_uses_loopback(linux: Shell) -> None:
    result = linux("""
HAS_SYSTEMD=true
SKIP_MANAGED_TOOLS=false
run_task() { shift; "$@"; }
mise() { [[ "$*" == "-C $DOTFILES_DIR run setup-pitchfork 127.0.0.1" ]]; }
phase_pitchfork
""")
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("first_port", [0, 443, 1024])
def test_caddy_install_grants_bind_permission_when_required(
    linux: Shell, first_port: int
) -> None:
    config = tomllib.loads((ROOT / "home/dot_config/mise/config.toml").read_text())
    hook = config["tools"]["http:caddy-cf"]["postinstall"]
    result = linux(
        f"FIRST_PORT={first_port}\nHOOK={shlex.quote(hook)}\n"
        + r"""
export FIRST_PORT MISE_TOOL_INSTALL_PATH="$HOME/mise installs/caddy"
sysctl() {
  [[ "$*" == '-n net.ipv4.ip_unprivileged_port_start' ]]
  printf '%s\n' "$FIRST_PORT"
}
sudo() {
  [[ $# == 3 && $1 == setcap && $2 == cap_net_bind_service=+ep ]]
  [[ $3 == "$MISE_TOOL_INSTALL_PATH/caddy-cf" ]]
  printf granted > "$HOME/capability"
}
export -f sysctl sudo
bash -e -c "$HOOK"
if [[ $FIRST_PORT -gt 443 ]]; then
  test -s "$HOME/capability"
else
  test ! -e "$HOME/capability"
fi
"""
    )
    assert result.returncode == 0, result.stdout + result.stderr
