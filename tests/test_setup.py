import os
import re
import shlex
import subprocess
import tomllib
from collections.abc import Callable
from pathlib import Path

import pytest
from conftest import ROOT

Shell = Callable[[str], subprocess.CompletedProcess[str]]


def herdr_hook(profile: str = "full", skip: str = "false") -> str:
    result = subprocess.run(
        [
            "chezmoi",
            "execute-template",
            "--override-data",
            '{"chezmoi":{"os":"linux"}}',
        ],
        input=(ROOT / "home/run_onchange_after_herdr_jj_plugin.sh.tmpl").read_text(),
        env={
            **os.environ,
            "DOTFILES_PROFILE": profile,
            "DOTFILES_SKIP_MANAGED_TOOLS": skip,
        },
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout


@pytest.fixture
def linux(tmp_path: Path) -> Shell:
    proc_version = tmp_path / "proc-version"
    proc_version.write_text("Linux version 6.8.0-generic\n")
    env = {
        **os.environ,
        "HOME": str(tmp_path),
        "PATH": "/usr/bin:/bin",
        "TMPDIR": str(tmp_path),
        "DOTFILES_ASSUME_YES": "true",
        "DOTFILES_PROFILE": "core",
        "DOTFILES_DIR": str(ROOT),
        "DOTFILES_WITH": "",
        "DOTFILES_SKIP_MANAGED_TOOLS": "false",
        "XDG_CONFIG_HOME": str(tmp_path / ".config"),
        "HOST_PROC_VERSION": str(proc_version),
        "HOST_SYSTEMD_DIR": str(tmp_path / "no-systemd"),
    }

    def execute(script: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "bash",
                "-Eeuo",
                "pipefail",
                "-c",
                'source "$DOTFILES_DIR/setup/linux.sh"\n' + script,
            ],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    return execute


@pytest.mark.parametrize("stage", ["mise", "clone", "install", "link"])
def test_herdr_jj_hook_retries_failures_and_is_idempotent(
    linux: Shell, stage: str
) -> None:
    hook = herdr_hook()
    assert "{{" not in hook
    result = linux(
        f"HOOK={shlex.quote(hook)}\nFAIL_STAGE={stage}\n"
        + """
export FAIL_STAGE DOTFILES_PROFILE=full DOTFILES_SKIP_MANAGED_TOOLS=false
printf '/home/old-user/tools/herdr-jj-workspaces\n' > "$HOME/linked"
call() {
  printf '%s\n' "$1" >> "$HOME/calls"
  [[ $FAIL_STAGE != "$1" ]] || return 17
}
mise() {
  [[ $MISE_AUTO_INSTALL == false ]]
  [[ "$*" == 'install --quiet uv github:herdrdev/herdr' ]] || return 99
  call mise
}
git() {
  call clone || return $?
  [[ "${*:1:3}" == 'clone --quiet https://github.com/aria-amini/tools' ]] \\
    || return 99
  [[ "$4" == "$HOME/tools/herdr-jj-workspaces" ]] || return 99
  mkdir -p "$HOME/tools/herdr-jj-workspaces/.git"
}
uv() {
  call install || return $?
  expected='tool install --quiet --python 3.14 --editable '
  expected+="$HOME/tools/herdr-jj-workspaces/herdr-jj-workspaces"
  [[ "$*" == "$expected" ]] || return 99
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/herdr-jj"
  chmod +x "$HOME/.local/bin/herdr-jj"
}
herdr() {
  local plugin_path="$HOME/tools/herdr-jj-workspaces/herdr-jj-workspaces/herdr-plugin"
  case "$*" in
  "plugin link $plugin_path")
    call link || return $?
    printf '%s\n' "$plugin_path" > "$HOME/linked"
    ;;
  *) return 99 ;;
  esac
}
export -f call mise git uv herdr
if bash -c "$HOOK"; then exit 99; else [[ $? == 17 ]]; fi
FAIL_STAGE=''
bash -c "$HOOK"
plugin_path="$HOME/tools/herdr-jj-workspaces/herdr-jj-workspaces/herdr-plugin"
[[ $(< "$HOME/linked") == "$plugin_path" ]]
cp "$HOME/calls" "$HOME/first-calls"
bash -c "$HOOK"
previous=$(grep -Ec 'clone|install' "$HOME/first-calls")
current=$(grep -Ec 'clone|install' "$HOME/calls")
[[ $current == "$previous" ]]
previous=$(grep -c link "$HOME/first-calls")
current=$(grep -c link "$HOME/calls")
[[ $current == "$((previous + 1))" ]]
"""
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count("Herdr jj plugin         ready") == 2


@pytest.mark.parametrize(
    ("profile", "skip"), [("core", "false"), ("full", "true"), ("core", "true")]
)
def test_herdr_jj_hook_respects_setup_selection(
    linux: Shell, profile: str, skip: str
) -> None:
    hook = herdr_hook(profile, skip)
    assert hook == ""
    result = linux(
        f"HOOK={shlex.quote(hook)}\n"
        f"export DOTFILES_PROFILE={profile} DOTFILES_SKIP_MANAGED_TOOLS={skip}\n"
        + """
mise() { printf 'unexpected install\n'; return 99; }
export -f mise
bash -c "$HOOK"
test ! -e "$HOME/tools/herdr-jj-workspaces"
"""
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout == ""


def test_herdr_jj_hook_shellcheck() -> None:
    hook = herdr_hook()
    result = subprocess.run(
        ["shellcheck", "--shell=bash", "-"],
        input=hook,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_herdr_jj_hook_runs_only_on_content_changes(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    name = "run_onchange_after_herdr_jj_plugin.sh.tmpl"
    hook = source / name
    hook.write_text((ROOT / "home" / name).read_text())
    home = tmp_path / "home"
    binaries = home / ".local/bin"
    binaries.mkdir(parents=True)
    (home / "tools/herdr-jj-workspaces/.git").mkdir(parents=True)
    for tool in ("mise", "herdr", "herdr-jj"):
        binary = binaries / tool
        binary.write_text('#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$HOME/calls"\n')
        binary.chmod(0o755)

    def apply(profile: str) -> None:
        subprocess.run(
            [
                "chezmoi",
                "--config",
                str(tmp_path / "config.toml"),
                "--source",
                str(source),
                "--destination",
                str(home),
                "--persistent-state",
                str(tmp_path / "state.boltdb"),
                "--override-data",
                '{"chezmoi":{"os":"linux"}}',
                "apply",
            ],
            env={
                **os.environ,
                "HOME": str(home),
                "DOTFILES_PROFILE": profile,
                "DOTFILES_SKIP_MANAGED_TOOLS": "false",
            },
            text=True,
            capture_output=True,
            check=True,
        )

    apply("core")
    calls = home / "calls"
    assert not calls.exists()
    apply("full")
    first_calls = calls.read_text()
    assert "plugin link" in first_calls
    apply("full")
    (source / "dot_unrelated").write_text("unrelated change\n")
    apply("full")
    assert calls.read_text() == first_calls
    hook.write_text(hook.read_text().replace("ready", "updated"))
    apply("full")
    assert calls.read_text() == first_calls * 2


def test_transcripts_are_private_and_unique(linux: Shell) -> None:
    logs: list[Path] = []
    for _ in range(2):
        result = linux("""
umask 022
phase_gum() { :; }
phase_apt() { :; }
phase_git() { :; }
phase_mise() { :; }
phase_github_notice() { printf 'mock authentication output\n'; }
phase_nix() { :; }
phase_dotfiles() { :; }
phase_shell() { :; }
main
""")
        assert result.returncode == 0, result.stderr
        match = re.search(r"^transcript: (.+)$", result.stdout, re.MULTILINE)
        assert match is not None, result.stdout
        log = Path(match.group(1))
        assert log.stat().st_mode & 0o777 == 0o600
        assert "mock authentication output" in log.read_text()
        logs.append(log)
    assert logs[0] != logs[1]


def test_privileged_task_preserves_arguments_and_failure(linux: Shell) -> None:
    result = linux("""
need_sudo() { printf 'sudo checked\n'; }
sudo() { "$@"; }
probe() {
  [[ "$#" == 2 && "$1" == 'two words' && "$2" == "a'b" ]] || return 99
  return 17
}
if run_task 'Probe' --sudo probe 'two words' "a'b"; then exit 1; else rc=$?; fi
[[ $rc == 17 ]]
""")
    assert result.returncode == 0, result.stderr
    assert "sudo checked" in result.stdout
    assert "✓ Probe" not in result.stdout


@pytest.mark.parametrize("status", [0, 17])
def test_dotfile_apply_captures_output_and_preserves_failures(
    linux: Shell, tmp_path: Path, status: int
) -> None:
    binary = tmp_path / "bin" / "chezmoi"
    binary.parent.mkdir()
    binary.write_text("""#!/usr/bin/env bash
[[ "$1" == --source && "$2" == "$DOTFILES_DIR" ]] || exit 99
[[ "${*:3}" == '--no-tty --error-on-conflict apply' ]] || exit 98
[[ $DOTFILES_PROFILE == full && $DOTFILES_SKIP_MANAGED_TOOLS == true ]] || exit 97
printf '{"plugin":"aamini.jj"}\n'
exit "$APPLY_STATUS"
""")
    binary.chmod(0o755)
    script = f"""
source "$DOTFILES_DIR/setup/linux.sh"
export PATH="$HOME/bin:$PATH" APPLY_STATUS={status}
PROFILE=full
SKIP_MANAGED_TOOLS=true
INTERACTIVE=true
LOG_FILE="$HOME/transcript.log"
gum() {{
  if [[ "$1" == spin ]]; then
    while [[ "$1" != -- ]]; do shift; done
    shift; "$@"
  else
    printf '%s\\n' "${{*: -1}}"
  fi
}}
if phase_dotfiles; then rc=0; else rc=$?; fi
[[ $rc == {status} ]]
grep -q 'aamini.jj' "$LOG_FILE"
grep -q 'chezmoi --source' "$LOG_FILE"
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr
    if status == 0:
        assert "aamini.jj" not in result.stdout
        assert "chezmoi --source" not in result.stdout
        assert re.search(r"✓ Dotfiles\s+applied", result.stdout)
    else:
        assert "aamini.jj" in result.stdout
        assert "✓ Dotfiles" not in result.stdout


@pytest.mark.parametrize(
    ("steps", "sections"),
    [
        ("", ["System", "Dotfiles", "Developer Tools", "Summary"]),
        (
            "docker,tailscale,pitchfork,t3",
            [
                "System",
                "Dotfiles",
                "Developer Tools",
                "Services",
                "Summary",
            ],
        ),
        (
            "t3",
            [
                "System",
                "Dotfiles",
                "Developer Tools",
                "Services",
                "Summary",
            ],
        ),
    ],
)
def test_optional_sections(linux: Shell, steps: str, sections: list[str]) -> None:
    result = linux(f"""
PROFILE=full
OPTIONAL_STEPS='{steps}'
validate_optional_steps
configure_sections
for entry in "${{SECTIONS[@]}}"; do
  printf '%s\n' "${{entry%%|*}}"
done
[[ "${{SECTIONS[0]}}" == 'System|apt git mise nix' ]]
""")
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == sections


@pytest.mark.parametrize("steps", ["invalid", "docker,invalid"])
def test_invalid_optional_step_fails_before_setup(linux: Shell, steps: str) -> None:
    result = linux(f"""
PROFILE=full
OPTIONAL_STEPS='{steps}'
phase_gum() {{ printf 'unexpected install\n'; }}
main
""")
    assert result.returncode != 0
    assert "unknown optional step: invalid" in result.stderr
    assert "unexpected install" not in result.stdout


def test_core_rejects_optional_steps(linux: Shell) -> None:
    result = linux("OPTIONAL_STEPS=tailscale; validate_optional_steps")
    assert result.returncode != 0
    assert "--with requires the full profile" in result.stderr


@pytest.mark.parametrize("selection", ["", "mise_tools\\ntailscale\\nt3"])
def test_optional_menu_controls_the_phase_list(linux: Shell, selection: str) -> None:
    script = f"""
source "$DOTFILES_DIR/setup/linux.sh"
PROFILE=full
INTERACTIVE=true
gum() {{
  if [[ "$1" == choose ]]; then
    printf '{selection}'
  else
    printf '%s\\n' "${{*: -1}}"
  fi
}}
configure_sections
printf 'selected=%s\\n' "$OPTIONAL_STEPS"
printf 'skip-managed=%s\\n' "$SKIP_MANAGED_TOOLS"
printf '%s\\n' "${{SECTIONS[@]}}"
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr
    if selection:
        assert "selected=tailscale,t3" in result.stdout
        assert "Services|tailscale t3" in result.stdout
        assert "skip-managed=false" in result.stdout
    else:
        assert "selected=\n" in result.stdout
        assert "Services|" not in result.stdout
        assert "Workspaces|" not in result.stdout
        assert "Developer Tools|" not in result.stdout
        assert "skip-managed=true" in result.stdout
    assert "Docker|" not in result.stdout
    assert "Workspaces" not in result.stdout


def test_bootstrap_forwards_optional_steps_in_preview(linux: Shell) -> None:
    result = linux(
        'bash "$DOTFILES_DIR/bootstrap.sh" '
        "--dry-run --yes --with t3 --skip-managed-tools"
    )
    assert result.returncode == 0, result.stderr
    assert "Optional steps: t3" in result.stdout
    assert "Skip managed tools: true" in result.stdout


@pytest.mark.parametrize("branch", ["", "cleanup"])
def test_bootstrap_runs_setup_from_repository_root(
    linux: Shell, tmp_path: Path, branch: str
) -> None:
    repo = tmp_path / "dotfiles repo"
    (repo / "home").mkdir(parents=True)
    (repo / "setup").mkdir()
    (repo / ".chezmoiroot").write_text("home\n")
    (repo / "setup" / "linux.sh").write_text(
        '[[ "$DOTFILES_DIR" == "$FAKE_REPO" ]] || exit 99\n'
        '[[ "$DOTFILES_SKIP_MANAGED_TOOLS" == true ]] || exit 95\n'
        'printf "setup reached repository root\\n"\n'
    )
    binary = tmp_path / ".local" / "bin" / "chezmoi"
    binary.parent.mkdir(parents=True)
    binary.write_text("""#!/usr/bin/env bash
if [[ "$1" == --source ]]; then
  [[ "$2" == "$FAKE_REPO" ]] || exit 96
  shift 2
fi
case "$1" in
init) [[ "${*:2}" == "$EXPECTED_INIT" ]] ;;
source-path) printf '%s/home\\n' "$FAKE_REPO" ;;
execute-template)
  [[ "$2" == '{{ .chezmoi.workingTree }}' ]] || exit 98
  printf '%s\\n' "$FAKE_REPO"
  ;;
*) exit 97 ;;
esac
""")
    binary.chmod(0o755)
    flags = ""
    expected_init = "--use-builtin-git=true aria-amini"
    if branch:
        flags = f" --branch {branch} --source {shlex.quote(str(repo))}"
        expected_init = f"--use-builtin-git=true --branch {branch} aria-amini"
    script = (
        f"export FAKE_REPO={shlex.quote(str(repo))}\n"
        f"export EXPECTED_INIT={shlex.quote(expected_init)}\n"
        f'bash "$DOTFILES_DIR/bootstrap.sh" --yes --skip-managed-tools{flags}'
    )
    result = linux(script)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "setup reached repository root" in result.stdout
    (repo / "setup" / "linux.sh").unlink()
    result = linux(script)
    assert result.returncode != 0
    assert "use --source DIR --branch BRANCH for a fresh clone" in result.stderr


def test_system_versions_do_not_bootstrap_github_cli(linux: Shell) -> None:
    result = linux("""
mise() {
  case "$*" in
  --version) printf '2026.10.1 linux-x64\n' ;;
  *) return 99 ;;
  esac
}
run() { printf 'unexpected bootstrap install\n'; return 99; }
phase_mise
docker() { printf 'Docker version 29.8.2, build abc\n'; }
show_version Docker 2 docker --version
""")
    assert result.returncode == 0, result.stderr
    versions = dict(re.findall(r"^  ✓ (.+?)\s+(\S+)$", result.stdout, re.MULTILINE))
    assert versions == {
        "Mise": "2026.10.1",
        "Docker": "29.8.2",
    }
    assert "Installing" not in result.stdout
    assert "unexpected bootstrap install" not in result.stdout


@pytest.mark.parametrize("state", ["absent", "authenticated", "unauthenticated"])
def test_github_summary_never_installs_or_prompts(
    linux: Shell, tmp_path: Path, state: str
) -> None:
    binary = tmp_path / "bin" / "gh"
    binary.parent.mkdir()
    binary.write_text("""#!/usr/bin/env bash
[[ $MISE_AUTO_INSTALL == false && $MISE_OFFLINE == true ]] || exit 99
printf '%s\n' "$*" >> "$HOME/gh-calls"
case "$*" in
--version) [[ $GH_STATE != absent ]] ;;
'auth status') [[ $GH_STATE == authenticated ]] ;;
*) exit 99 ;;
esac
""")
    binary.chmod(0o755)
    result = linux(f"""
export PATH="$HOME/bin:$PATH" GH_STATE={state}
INTERACTIVE=true
gum_ui() {{ printf 'unexpected prompt\\n'; return 99; }}
phase_github_notice
printf '%s\\n' "${{NOTES[@]}}"
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "unexpected prompt" not in result.stdout
    assert ("Optional GitHub sign-in:" in result.stdout) == (state == "unauthenticated")
    calls = (tmp_path / "gh-calls").read_text().splitlines()
    assert calls == (
        ["--version"] if state == "absent" else ["--version", "auth status"]
    )


@pytest.mark.parametrize("status", [0, 17])
def test_live_output_streams_to_tty_and_preserves_logs(
    linux: Shell, status: int
) -> None:
    script = f"""
source "$DOTFILES_DIR/setup/linux.sh"
INTERACTIVE=true
gum() {{ :; }}
LOG_FILE="$HOME/transcript.log"
exec > >(tee -a "$LOG_FILE") 2>&1
rc=0
run 'Live probe' --live bash -c \\
  'printf "live output\\n"; sleep 0.3; exit {status}' || rc=$?
[[ $rc == {status} ]]
printf 'completed with %s\\n' "$rc"
sleep 0.05
grep -q 'live output' "$LOG_FILE"
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Live probe..." in result.stdout
    assert "live output" in result.stdout
    assert "\x1b[" not in result.stdout.replace("\x1b[?", "")
    assert result.stdout.count("live output") == 1
    assert f"completed with {status}" in result.stdout


def test_installed_services(linux: Shell) -> None:
    result = linux("""
docker() { :; }
tailscale() { :; }
mkdir -p "$XDG_CONFIG_HOME/systemd/user"
touch "$XDG_CONFIG_HOME/systemd/user/t3code.service"
for step in docker tailscale t3; do
  setup_step_installed "$step"
  setup_step_label "$step"; printf '\n'
done
""")
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "Docker",
        "Tailscale",
        "T3 Code",
    ]


def test_absent_services_and_residual_package_are_not_installed(linux: Shell) -> None:
    result = linux("""
command() {
  if [[ "$1" == -v && "$2" =~ ^(docker|tailscale|t3)$ ]]; then return 1; fi
  builtin command "$@"
}
dpkg-query() { printf 'deinstall ok config-files'; }
for step in docker tailscale t3; do
  if setup_step_installed "$step"; then exit 99; fi
done
""")
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""


def test_t3_cli_without_service_is_not_ready(linux: Shell) -> None:
    result = linux("t3() { :; }; if setup_step_installed t3; then exit 99; fi")
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""


def test_entry_versions_use_offline_probes_and_active_t3_runtime(linux: Shell) -> None:
    result = linux("""
timeout() {
  [[ $MISE_AUTO_INSTALL == false && $MISE_OFFLINE == true ]]
  [[ $MISE_NO_ENV == true && $MISE_NO_HOOKS == true ]]
  shift; "$@"
}
docker() { printf 'Docker version 29.7.2, build abc\n'; }
tailscale() { printf '1.102.3\n  commit: abc\n'; }
pitchfork() { printf 'pitchfork 2.28.0\n'; }
mkdir -p "$HOME/.t3/runtime"
printf '{"activeVersion":"0.0.40"}' > "$HOME/.t3/runtime/service-state.json"
jq() {
  [[ "$2" == '.activeVersion // empty' ]]
  printf '0.0.40\n'
}
for step in docker tailscale pitchfork t3; do
  printf '%s=' "$step"; setup_step_version "$step"; printf '\n'
done
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.splitlines() == [
        "docker=29.7.2",
        "tailscale=1.102.3",
        "pitchfork=2.28.0",
        "t3=0.0.40",
    ]


def test_missing_pitchfork_shim_does_not_count_as_installed(linux: Shell) -> None:
    result = linux("""
pitchfork() { return 1; }
timeout() { shift; "$@"; }
if setup_step_installed pitchfork; then exit 99; fi
setup_step_version pitchfork
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout == ""


@pytest.mark.parametrize(
    ("tools", "status"),
    [
        ("node 22 installed\\nuv 0.12 installed", "2/2 installed; sync"),
        ("uv 0.12 installed", "1/2 installed; install"),
        ("", "0/2 installed; install"),
        (
            "uv 0.12 installed\\nuv 0.13 installed\\nother 1 installed",
            "1/2 installed; install",
        ),
    ],
)
def test_managed_tools_status_is_offline(linux: Shell, tools: str, status: str) -> None:
    result = linux(f"""
managed_tool_names() {{ printf 'node\\nuv\\n'; }}
timeout() {{ shift; "$@"; }}
mise() {{
  [[ $MISE_OFFLINE == true && $MISE_NO_ENV == true && $MISE_NO_HOOKS == true ]]
  [[ "$*" == 'ls --installed --no-header' ]] || return 99
  printf '{tools}'
}}
managed_tools_status
""")
    assert result.returncode == 0, result.stderr
    assert result.stdout == status


def test_managed_tools_probe_failure_is_informational(linux: Shell) -> None:
    result = linux("""
managed_tool_names() { printf 'node\nuv\n'; }
timeout() { shift; "$@"; }
mise() { return 1; }
managed_tools_status
""")
    assert result.returncode == 0, result.stderr
    assert result.stdout == "?/2 installed; sync"


def test_fresh_machine_counts_the_source_catalog(linux: Shell) -> None:
    result = linux("""
command() {
  if [[ "$*" == '-v mise' ]]; then return 1; fi
  builtin command "$@"
}
managed_tools_status
""")
    assert result.returncode == 0, result.stdout + result.stderr
    catalog = tomllib.loads((ROOT / "home/dot_config/mise/config.toml").read_text())
    assert result.stdout == f"0/{len(catalog['tools'])} installed; install"


@pytest.mark.parametrize("skip", ["false", "true"])
def test_menu_detects_services_and_sets_managed_default(
    linux: Shell, skip: str
) -> None:
    script = f"""
source "$DOTFILES_DIR/setup/linux.sh"
PROFILE=full
INTERACTIVE=true
SKIP_MANAGED_TOOLS={skip}
docker() {{ :; }}
tailscale() {{ :; }}
setup_step_version() {{ printf '1.2.3'; }}
mkdir -p "$XDG_CONFIG_HOME/systemd/user"
touch "$XDG_CONFIG_HOME/systemd/user/t3code.service"
gum() {{
  if [[ "$1" == choose ]]; then
    printf '%s\\n' "$@" > "$HOME/menu-args"
    cat "$HOME/menu-args" > /dev/tty
    [[ "$SKIP_MANAGED_TOOLS" == true ]] || printf 'mise_tools\\n'
  else
    printf '%s\\n' "${{*: -1}}"
  fi
}}
configure_sections
if grep -E '[|](docker|tailscale|pitchfork|t3)$' "$HOME/menu-args"; then exit 99; fi
selected="$(grep -A 1 -- '--selected' "$HOME/menu-args")"
if [[ {skip} == false ]]; then
  [[ "$selected" == *'Developer tools'* ]]
else
  [[ "$selected" != *'Developer tools'* ]]
fi
[[ "$selected" != *'Workspaces'* ]]
[[ "$SKIP_MANAGED_TOOLS" == {skip} ]]
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr
    assert re.search(r"✓ Docker\s+1\.2\.3\s+Ready", result.stdout)
    assert re.search(r"✓ T3 Code\s+1\.2\.3\s+Ready", result.stdout)


@pytest.mark.parametrize(
    ("version", "wsl"),
    [
        ("Linux version 5.15.167.4-microsoft-standard-WSL2", True),
        ("Linux version 6.8.0-generic", False),
    ],
)
def test_host_detects_wsl_from_the_kernel_version(
    linux: Shell, tmp_path: Path, version: str, wsl: bool
) -> None:
    (tmp_path / "proc-version").write_text(version + "\n")
    result = linux("host_is_wsl")
    assert (result.returncode == 0) is wsl


def test_host_detects_systemd(linux: Shell, tmp_path: Path) -> None:
    assert linux("host_has_systemd").returncode != 0
    (tmp_path / "no-systemd").mkdir()
    assert linux("host_has_systemd").returncode == 0


@pytest.mark.parametrize(
    ("step", "requested", "wsl", "selected"),
    [
        ("docker", "", False, True),
        ("docker", "", True, False),
        ("tailscale", "", True, True),
        ("docker", "docker", True, True),
        ("docker", "t3", False, False),
        ("t3", "t3", False, True),
        ("tailscale", "t3", False, False),
        ("mise_tools", "t3", True, True),
    ],
)
def test_default_selection_follows_host_and_request(
    linux: Shell, step: str, requested: str, wsl: bool, selected: bool
) -> None:
    host = "return 0" if wsl else "return 1"
    result = linux(
        f"host_is_wsl() {{ {host}; }}\nsetup_step_default_selected {step} '{requested}'"
    )
    assert (result.returncode == 0) is selected


def test_menu_preselects_only_the_requested_steps(linux: Shell) -> None:
    script = """
source "$DOTFILES_DIR/setup/linux.sh"
PROFILE=full
INTERACTIVE=true
OPTIONAL_STEPS=t3
setup_step_installed() { return 1; }
gum() {
  if [[ "$1" == choose ]]; then
    printf '%s\\n' "$@" > "$HOME/menu-args"
  fi
}
configure_sections
selected="$(grep -A 1 -- '--selected' "$HOME/menu-args")"
[[ "$selected" == *'T3 Code'* ]]
[[ "$selected" == *'Developer tools'* ]]
for label in Docker Tailscale Pitchfork; do
  [[ "$selected" != *"$label"* ]]
done
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr


def test_menu_does_not_preselect_docker_on_wsl(linux: Shell) -> None:
    script = """
source "$DOTFILES_DIR/setup/linux.sh"
PROFILE=full
INTERACTIVE=true
host_is_wsl() { return 0; }
setup_step_installed() { return 1; }
gum() {
  if [[ "$1" == choose ]]; then
    printf '%s\\n' "$@" > "$HOME/menu-args"
  fi
}
configure_sections
selected="$(grep -A 1 -- '--selected' "$HOME/menu-args")"
grep -q '[|]docker$' "$HOME/menu-args"
[[ "$selected" != *Docker* ]]
for label in Tailscale Pitchfork 'T3 Code'; do
  [[ "$selected" == *"$label"* ]]
done
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr


def test_docker_desktop_link_counts_as_installed(linux: Shell, tmp_path: Path) -> None:
    result = linux(f"""
command() {{
  if [[ "$1" == -v && "$2" == docker ]]; then return 1; fi
  builtin command "$@"
}}
DOCKER_CLIENT_LINK={shlex.quote(str(tmp_path / "docker"))}
if docker_installed; then exit 99; fi
ln -s /nonexistent/docker "$DOCKER_CLIENT_LINK"
docker_installed
""")
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize(
    ("release", "expected"),
    [
        ("ID=ubuntu\nVERSION_CODENAME=noble\n", "noble"),
        (
            "ID=linuxmint\nID_LIKE=ubuntu\nVERSION_CODENAME=wilma\nUBUNTU_CODENAME=noble\n",
            "noble",
        ),
    ],
)
def test_docker_repository_uses_the_ubuntu_codename(
    linux: Shell, tmp_path: Path, release: str, expected: str
) -> None:
    os_release = tmp_path / "os-release"
    os_release.write_text(release)
    result = linux(f"HOST_OS_RELEASE={shlex.quote(str(os_release))}; ubuntu_codename")
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout == expected


def test_docker_repository_rejects_other_distributions(
    linux: Shell, tmp_path: Path
) -> None:
    os_release = tmp_path / "os-release"
    os_release.write_text("ID=fedora\nVERSION_CODENAME=\n")
    result = linux(
        f'HOST_OS_RELEASE={shlex.quote(str(os_release))}\ncodename="$(ubuntu_codename)"'
    )
    assert result.returncode != 0
    assert "Ubuntu only" in result.stderr


WSL_CONFS = [
    None,
    "[boot]\nsystemd=true\n",
    "[interop]\nenabled=true\n",
    (
        "# keep me\n[interop]\nappendWindowsPath = true\nenabled=true\n"
        "[boot]\nsystemd=true\n"
    ),
    "[interop]\nappendWindowsPath=falsehood\n",
    "[boot]\nappendWindowsPath=false\n",
]


def git_config(path: Path, *args: str) -> list[str]:
    result = subprocess.run(
        ["git", "config", "-f", str(path), *args],
        capture_output=True,
        text=True,
    )
    return result.stdout.split()


@pytest.mark.parametrize("conf", WSL_CONFS)
def test_wsl_interop_step_disables_windows_path_once(
    linux: Shell, tmp_path: Path, conf: str | None
) -> None:
    path = tmp_path / "wsl.conf"
    if conf is not None:
        path.write_text(conf)
    result = linux(f"""
WSL_CONF={shlex.quote(str(path))}
run_task() {{ shift; [[ $1 != --sudo ]] || shift; "$@"; }}
if wsl_windows_path_disabled; then exit 99; fi
phase_wsl_interop
phase_wsl_interop
wsl_windows_path_disabled
wsl_automount_disabled
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert git_config(path, "--get-all", "interop.appendWindowsPath") == ["false"]
    assert git_config(path, "--get-all", "automount.enabled") == ["false"]
    for line in (conf or "").splitlines():
        if "interop" not in line and "appendWindowsPath" not in line:
            assert line in path.read_text(), line


@pytest.mark.parametrize(
    "conf",
    [
        "[interop]\nappendWindowsPath=false\n",
        "[interop]\nappendWindowsPath = false # keep\n",
        "[Interop]\nappendWindowsPath = False\n",
    ],
)
def test_wsl_windows_path_already_disabled(
    linux: Shell, tmp_path: Path, conf: str
) -> None:
    path = tmp_path / "wsl.conf"
    path.write_text(conf)
    result = linux(f"WSL_CONF={shlex.quote(str(path))}; wsl_windows_path_disabled")
    assert result.returncode == 0, result.stdout + result.stderr


def test_wsl_interop_step_only_exists_on_wsl(linux: Shell) -> None:
    result = linux("setup_step_available wsl_interop")
    assert result.returncode != 0
    result = linux("""
OPTIONAL_STEPS=wsl_interop
PROFILE=full
validate_optional_steps
""")
    assert "not available on this host" in result.stderr
    result = linux("""
host_is_wsl() { return 0; }
OPTIONAL_STEPS=wsl_interop
PROFILE=full
validate_optional_steps
setup_step_default_selected wsl_interop && exit 99
setup_step_default_selected wsl_interop wsl_interop
""")
    assert result.returncode == 0, result.stdout + result.stderr


def test_docker_client_only_skips_engine_setup(linux: Shell) -> None:
    result = linux("""
docker_installed() { return 0; }
docker_engine_installed() { return 1; }
docker() { printf 'Docker version 29.8.2, build abc\\n'; }
run_task() { printf 'RAN: %s\\n' "$1"; }
phase_docker
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "RAN:" not in result.stdout
    assert "docker client only" in result.stdout


@pytest.mark.parametrize("skip", ["false", "true"])
def test_menu_selects_all_missing_options(linux: Shell, skip: str) -> None:
    script = f"""
source "$DOTFILES_DIR/setup/linux.sh"
PROFILE=full
INTERACTIVE=true
SKIP_MANAGED_TOOLS={skip}
setup_step_installed() {{ return 1; }}
gum() {{
  if [[ "$1" == choose ]]; then
    printf '%s\\n' "$@" > "$HOME/menu-args"
  fi
}}
configure_sections
selected="$(grep -A 1 -- '--selected' "$HOME/menu-args")"
for label in Docker Tailscale Pitchfork 'T3 Code'; do
  [[ "$selected" == *"$label"* ]]
done
if [[ {skip} == false ]]; then
  [[ "$selected" == *'Developer tools'* ]]
else
  [[ "$selected" != *'Developer tools'* ]]
fi
if grep -E 'Service not installed|not configured|Workspaces' "$HOME/menu-args"; then
  exit 99
fi
"""
    command = shlex.quote("bash -Eeuo pipefail -c " + shlex.quote(script))
    result = linux(f"script -q -e -c {command} /dev/null")
    assert result.returncode == 0, result.stdout + result.stderr


def test_full_debug_skip_applies_dotfiles_and_blocks_auto_install(linux: Shell) -> None:
    result = linux("""
PROFILE=full
SKIP_MANAGED_TOOLS=true
phase_gum() { :; }
phase_apt() { :; }
phase_git() { :; }
phase_mise() { :; }
phase_github_notice() { :; }
phase_nix() { :; }
phase_dotfiles() { printf 'dotfiles applied\n'; }
run() { printf 'unexpected tool install\n'; return 99; }
phase_shell() { [[ "$MISE_AUTO_INSTALL" == false ]]; }
main
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "dotfiles applied" in result.stdout
    assert "Developer Tools|" not in result.stdout
    assert "▸ [3/3] Summary" in result.stdout
    assert "Workspaces" not in result.stdout
    assert "unexpected tool install" not in result.stdout


def test_skipped_catalog_installs_only_selected_service_prerequisites(
    linux: Shell,
) -> None:
    result = linux("""
host_has_systemd() { return 0; }
SKIP_MANAGED_TOOLS=true
run() { printf '%s\n' "$*"; }
run_task() { :; }
root_plain() { return 1; }
write_t3_settings() { :; }
mise() { printf '/tools/node/bin/node\n'; }
mkdir -p "$HOME/.local/state/pitchfork/proxy"
touch "$HOME/.local/state/pitchfork/proxy/ca.pem"
phase_pitchfork
phase_t3
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "--live mise install pitchfork" in result.stdout
    assert "--live mise install node opencode jq" in result.stdout


def test_debug_runner_forwards_managed_skip(linux: Shell, tmp_path: Path) -> None:
    binary = tmp_path / "bin" / "docker"
    binary.parent.mkdir()
    binary.write_text("""#!/usr/bin/env bash
case "$1" in
info) exit 0 ;;
build) printf 'debug-image\n' ;;
run) printf '<%s>\n' "$@" ;;
*) exit 99 ;;
esac
""")
    binary.chmod(0o755)
    result = linux(
        f"export PATH={shlex.quote(str(binary.parent))}:$PATH\n"
        "export TERM=xterm-256color COLORTERM=truecolor\n"
        'bash "$DOTFILES_DIR/scripts/debug-linux.sh" '
        "--skip-managed-tools --yes --no-shell"
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "<DOTFILES_SKIP_MANAGED_TOOLS=true>" in result.stdout
    assert "<DOTFILES_PROFILE=full>" in result.stdout
    assert "<TERM=xterm-256color>" in result.stdout
    assert "<COLORTERM=truecolor>" in result.stdout


def run_age_setup(
    tmp_path: Path, *, key_file: bool, config: str | None = None, encrypted: bool = True
) -> tuple[subprocess.CompletedProcess[str], Path]:
    home = tmp_path / "home"
    source = tmp_path / "source"
    home.mkdir()
    source.mkdir()
    if encrypted:
        (source / "encrypted_token.age").write_text("ciphertext")
    env = {
        **{k: v for k, v in os.environ.items() if k != "XDG_CONFIG_HOME"},
        "HOME": str(home),
        "DOTFILES_DIR": str(source),
        "DOTFILES_ASSUME_YES": "true",
    }
    if config is not None:
        (home / ".config/chezmoi").mkdir(parents=True)
        (home / ".config/chezmoi/chezmoi.toml").write_text(config)
    if key_file:
        key = tmp_path / "key.txt"
        subprocess.run(
            ["chezmoi", "age-keygen", "--output", str(key)], check=True, env=env
        )
        env["DOTFILES_AGE_KEY_FILE"] = str(key)
    result = subprocess.run(
        ["bash", "-c", f'source "{ROOT}/setup/common.sh"; ensure_age_identity'],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    return result, home / ".config/chezmoi"


def test_age_key_file_configures_encryption(tmp_path: Path) -> None:
    result, chezmoi_dir = run_age_setup(tmp_path, key_file=True)
    assert result.returncode == 0, result.stderr
    assert (chezmoi_dir / "age-key.txt").stat().st_mode & 0o777 == 0o600
    config = tomllib.loads((chezmoi_dir / "chezmoi.toml").read_text())
    assert config["encryption"] == "age"
    assert config["age"]["recipient"].startswith("age1")
    assert "skipped" not in result.stderr


def test_missing_age_key_skips_with_hint(tmp_path: Path) -> None:
    result, chezmoi_dir = run_age_setup(tmp_path, key_file=False)
    assert result.returncode == 0
    assert "Encrypted credentials skipped" in result.stderr
    assert not (chezmoi_dir / "chezmoi.toml").exists()


def test_existing_config_is_not_overwritten(tmp_path: Path) -> None:
    result, chezmoi_dir = run_age_setup(tmp_path, key_file=True, config="[data]\n")
    assert result.returncode == 0
    assert (chezmoi_dir / "chezmoi.toml").read_text() == "[data]\n"
    assert 'encryption = "age"' in result.stderr


def test_age_setup_ignores_repos_without_encrypted_files(tmp_path: Path) -> None:
    result, chezmoi_dir = run_age_setup(tmp_path, key_file=True, encrypted=False)
    assert result.returncode == 0
    assert result.stderr == ""
    assert not chezmoi_dir.exists()


def test_invalid_age_key_file_is_rejected_and_replaceable(tmp_path: Path) -> None:
    bad = tmp_path / "bad.txt"
    bad.write_text("not a key\n")
    source = tmp_path / "source"
    source.mkdir()
    (source / "x.age").write_text("c")
    chezmoi_dir = tmp_path / "home/.config/chezmoi"
    env = {
        **{k: v for k, v in os.environ.items() if k != "XDG_CONFIG_HOME"},
        "HOME": str(tmp_path / "home"),
        "DOTFILES_DIR": str(source),
        "DOTFILES_ASSUME_YES": "true",
        "DOTFILES_AGE_KEY_FILE": str(bad),
    }
    run = lambda: subprocess.run(  # noqa: E731
        ["bash", "-c", f'source "{ROOT}/setup/common.sh"; ensure_age_identity'],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    first = run()
    assert first.returncode == 0
    assert "Age key is invalid" in first.stderr
    assert not (chezmoi_dir / "age-key.txt").exists()
    good = tmp_path / "good.txt"
    subprocess.run(
        ["chezmoi", "age-keygen", "--output", str(good)], check=True, env=env
    )
    env["DOTFILES_AGE_KEY_FILE"] = str(good)
    assert run().returncode == 0
    assert (chezmoi_dir / "chezmoi.toml").exists()


def test_age_config_follows_xdg_config_home(tmp_path: Path) -> None:
    xdg = tmp_path / "xdg"
    key = tmp_path / "key.txt"
    source = tmp_path / "source"
    source.mkdir()
    (source / "x.age").write_text("c")
    subprocess.run(["chezmoi", "age-keygen", "--output", str(key)], check=True)
    result = subprocess.run(
        ["bash", "-c", f'source "{ROOT}/setup/common.sh"; ensure_age_identity'],
        env={
            **os.environ,
            "HOME": str(tmp_path / "home"),
            "XDG_CONFIG_HOME": str(xdg),
            "DOTFILES_DIR": str(source),
            "DOTFILES_AGE_KEY_FILE": str(key),
        },
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert (xdg / "chezmoi/chezmoi.toml").exists()


def test_non_age_encryption_config_is_reported(tmp_path: Path) -> None:
    result, _ = run_age_setup(tmp_path, key_file=True, config='encryption = "gpg"\n')
    assert result.returncode == 0
    assert 'encryption = "age"' in result.stderr
