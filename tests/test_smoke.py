import re
from pathlib import Path

import pytest
from conftest import ROOT
from testcontainers.core.container import DockerContainer

pytestmark = [pytest.mark.e2e, pytest.mark.timeout(1200)]
SNAPSHOT = Path(__file__).with_name("snapshots") / "linux-core.txt"
ARTIFACTS = ROOT / ".pytest_cache" / "smoke"

PREPARE = """
set -eu
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates sudo
useradd --create-home --shell /bin/bash smoke
printf 'smoke ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/smoke
chmod 0440 /etc/sudoers.d/smoke
mkdir /dotfiles
cp -r /source/home /source/setup /source/.chezmoiroot /dotfiles/
chown -R smoke:smoke /dotfiles
"""

INSTALL = """
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$PATH"
curl -fsSL --retry 3 https://get.chezmoi.io -o /tmp/chezmoi-installer.sh
sh /tmp/chezmoi-installer.sh -b "$HOME/.local/bin"
bash /dotfiles/setup/linux.sh
"""

VERIFY = """
set -Eeuo pipefail
trap 'printf "Verification failed: %s\\n" "$BASH_COMMAND" >&2' ERR
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export PATH="$HOME/.nix-profile/bin:$PATH"
gum --version
git --version
zsh --version
mise --version
nix --version
if MISE_AUTO_INSTALL=false gh --version > /dev/null 2>&1; then exit 99; fi
for tool in uv herdr; do
  if MISE_AUTO_INSTALL=false "$tool" --version > /dev/null 2>&1; then exit 99; fi
done
if command -v herdr-jj > /dev/null 2>&1; then exit 99; fi
test ! -e "$HOME/tools/herdr-jj-workspaces"
test "$(getent passwd smoke | cut -d: -f7)" = "$(command -v zsh)"
test -s "$HOME/.zshrc"
test -s "$HOME/.config/mise/config.toml"
test -x "$HOME/.config/mise/tasks/setup-pitchfork"
test -s "$HOME/AGENTS.md"
chezmoi --source /dotfiles --no-tty --error-on-conflict verify --exclude scripts
logs=(/tmp/dotfiles-setup-*.log)
test "${#logs[@]}" = 1
test "$(stat -c %a "${logs[0]}")" = 600
grep -q '✓ Setup complete' "${logs[0]}"
chezmoi --source /dotfiles --no-tty --error-on-conflict apply --include scripts \\
  > /tmp/hook-reapply.txt
test ! -s /tmp/hook-reapply.txt
test -z "$(chezmoi --source /dotfiles \\
  --override-data '{"chezmoi":{"os":"darwin"}}' execute-template \\
  < /dotfiles/home/run_after_herdr_jj_plugin.sh.tmpl)"
"""

VERIFY_FULL_PLUGIN = """
set -Eeuo pipefail
trap 'printf "Full-profile verification failed: %s\\n" "$BASH_COMMAND" >&2' ERR
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export DOTFILES_PROFILE=full DOTFILES_SKIP_MANAGED_TOOLS=false MISE_AUTO_INSTALL=false
chezmoi --source /dotfiles --no-tty --error-on-conflict apply --include scripts
uv --version
herdr --version
command -v herdr-jj
herdr plugin list
herdr plugin list | grep -q aamini.jj
chezmoi --source /dotfiles --no-tty --error-on-conflict apply --include scripts
herdr plugin list | grep -q aamini.jj
"""

VERIFY_COLOR = """
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$PATH"
source /dotfiles/setup/linux.sh
INTERACTIVE=true
LOG_FILE="$HOME/ui-transcript.log"
exec > >(tee -a "$LOG_FILE") 2>&1
ok 'Color probe' 'ready'
sleep 0.05
grep -q 'Color probe' "$LOG_FILE"
if grep -q $'\\033' "$LOG_FILE"; then exit 99; fi
"""


def progress_snapshot(output: str) -> str:
    lines: list[str] = []
    for line in output.splitlines():
        if line.startswith("▸ [") or line == "✓ Setup complete":
            lines.append(line)
        elif line.startswith("  ✓ "):
            label = line[4:].strip()
            label = re.sub(
                r"^(Gum|Zsh|Git|Mise|GitHub CLI|uv|Herdr|Nix)\s{2,}.*$", r"\1", label
            )
            lines.append(f"✓ {label}")
        elif line.startswith("  ! "):
            lines.append(line.strip())
        elif line.startswith(("Optional GitHub sign-in:", "Open a new login session")):
            lines.append(line)
    return "\n".join(lines) + "\n"


def execute(
    container: DockerContainer,
    script: str,
    name: str,
    *,
    user: str = "smoke",
    tty: bool = False,
) -> str:
    result = container.get_wrapped_container().exec_run(
        ["bash", "-c", script],
        user=user,
        tty=tty,
        environment={
            "HOME": "/root" if user == "root" else "/home/smoke",
            "USER": user,
            "DOTFILES_DIR": "/dotfiles",
            "DOTFILES_PROFILE": "core",
            "DOTFILES_ASSUME_YES": "true",
        },
    )
    assert isinstance(result.output, bytes)
    output = result.output.decode("utf-8", errors="replace")
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    (ARTIFACTS / f"{name}.log").write_text(output)
    assert result.exit_code == 0, f"{name} failed:\n{output}"
    return output


def test_linux_core_setup() -> None:
    with (
        DockerContainer("ubuntu:24.04", docker_client_kw={"timeout": 1200})
        .with_volume_mapping(str(ROOT), "/source", mode="ro")
        .with_command("sleep infinity")
    ) as container:
        execute(container, PREPARE, "prepare", user="root")
        output = execute(container, INSTALL, "install")
        actual = progress_snapshot(output)
        (ARTIFACTS / "progress.txt").write_text(actual)
        execute(container, VERIFY, "verify")
        colors = execute(container, VERIFY_COLOR, "colors", tty=True)
        assert "\x1b[38;5;82m" in colors
        assert "\x1b]11;" not in colors
        assert "\x1b[6n" not in colors
        assert actual == SNAPSHOT.read_text()
        execute(container, VERIFY_FULL_PLUGIN, "full-plugin")
