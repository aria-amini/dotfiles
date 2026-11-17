import json
import os
import pwd
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest
from conftest import ROOT, mise_tools
from test_setup import Shell
from test_setup import linux as linux

# The fake applies `proxy add` and `proxy remove` the way pitchfork 2.29 does:
# `proxy add` keeps an existing namespace table, and `proxy remove` keeps all
# namespace tables.
FAKE_PITCHFORK = """
import json, os, sys
from pathlib import Path

import tomlkit

args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as file:
    file.write(json.dumps(args) + "\\n")
path = Path.home() / ".config/pitchfork/config.toml"
config = tomlkit.parse(path.read_text()) if path.exists() else tomlkit.document()
if args[:2] == ["proxy", "add"]:
    options = dict(zip(args[3::2], args[4::2], strict=True))
    namespace = options["--namespace"]
    slug = {"namespace": namespace, "daemon": options["--daemon"]}
    config.setdefault("slugs", tomlkit.table())[args[2]] = slug
    namespaces = config.setdefault("namespaces", tomlkit.table())
    namespaces.setdefault(namespace, {"dir": options["--dir"]})
elif args[:2] == ["proxy", "remove"]:
    config.get("slugs", {}).pop(args[2], None)
    if "slugs" in config and not config["slugs"]:
        del config["slugs"]
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(tomlkit.dumps(config))
"""


@pytest.fixture
def pitchfork_env(tmp_path: Path) -> dict[str, str]:
    binary = tmp_path / "bin/pitchfork"
    binary.parent.mkdir()
    binary.write_text(f"#!{sys.executable}\n{FAKE_PITCHFORK}")
    binary.chmod(0o755)
    return {
        **os.environ,
        "PATH": f"{binary.parent}:{os.environ['PATH']}",
        # The tests use tmp_path as a checkout, so HOME must be another folder.
        "HOME": str(tmp_path / "home"),
        "XDG_STATE_HOME": str(tmp_path / "xdg-state"),
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


def register(env: dict[str, str], *args: str) -> subprocess.CompletedProcess:
    return run_script("pitchfork-register", env, *args)


def calls(env: dict[str, str]) -> list[list[str]]:
    path = Path(env["CALLS"])
    return (
        [json.loads(line) for line in path.read_text().splitlines()]
        if path.exists()
        else []
    )


def config_path(env: dict[str, str]) -> Path:
    return Path(env["HOME"]) / ".config/pitchfork/config.toml"


def read_config(env: dict[str, str]) -> dict:
    path = config_path(env)
    return tomllib.loads(path.read_text()) if path.exists() else {}


def seed(env: dict[str, str], config: str) -> None:
    path = config_path(env)
    path.parent.mkdir(parents=True)
    path.write_text(config)


def local_namespace(root: Path) -> str | None:
    return tomllib.loads((root / "pitchfork.local.toml").read_text()).get("namespace")


def add_call(slug: str, root: Path, daemon: str = "dev") -> list[str]:
    return [
        *("proxy", "add", slug, "--daemon", daemon, "--dir", str(root)),
        *("--namespace", slug),
    ]


@pytest.fixture
def checkout(tmp_path: Path) -> Path:
    root = tmp_path / "checkout"
    root.mkdir()
    return root


def test_register_preserves_overrides_and_sets_checkout_specific_namespace(
    tmp_path: Path, pitchfork_env: dict[str, str]
) -> None:
    root = tmp_path / "animations"
    root.mkdir()
    local = root / "pitchfork.local.toml"
    local.write_text('namespace = "portfolio"\n[daemons.dev]\nport = 3005\n')
    result = register(pitchfork_env, "portfolio-animations", "--dir", str(root))
    assert result.returncode == 0, result.stderr
    assert result.stdout == "https://portfolio-animations.localhost\n"
    assert tomllib.loads(local.read_text()) == {
        "namespace": "portfolio-animations",
        "daemons": {"dev": {"port": 3005}},
    }
    assert calls(pitchfork_env) == [add_call("portfolio-animations", root)]
    assert read_config(pitchfork_env) == {
        "slugs": {
            "portfolio-animations": {
                "namespace": "portfolio-animations",
                "daemon": "dev",
            }
        },
        "namespaces": {"portfolio-animations": {"dir": str(root)}},
    }
    assert (tmp_path / "xdg-state/pitchfork-register.lock").exists()


def test_register_exits_early_on_full_match(
    checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    seed(pitchfork_env, '[settings.proxy]\ntld = "lab.example.dev"\n')
    for _ in range(2):
        result = register(pitchfork_env, "app", "--dir", str(checkout))
        assert result.returncode == 0, result.stderr
        assert result.stdout == "https://app.lab.example.dev\n"
    assert calls(pitchfork_env) == [add_call("app", checkout)]


@pytest.mark.parametrize(
    ("slug", "expected"),
    [
        ("app.worktree", "app-worktree"),
        ("My_App..Feature/X--", "my-app-feature-x"),
        ("a" * 62 + ".b", "a" * 62),
    ],
)
def test_register_normalizes_slug(
    slug: str, expected: str, checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    result = register(pitchfork_env, slug, "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert result.stdout == f"https://{expected}.localhost\n"
    assert local_namespace(checkout) == expected
    assert calls(pitchfork_env) == [add_call(expected, checkout)]


def test_register_rejects_empty_slug_without_changes(
    checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    result = register(pitchfork_env, "._.", "--dir", str(checkout))
    assert result.returncode == 2
    assert "no letters or digits" in result.stderr
    assert not (checkout / "pitchfork.local.toml").exists()
    assert not calls(pitchfork_env)


@pytest.mark.parametrize("tracked", ["pitchfork.toml", ".config/pitchfork.toml"])
def test_register_rejects_conflicting_namespace_without_changes(
    tracked: str, tmp_path: Path, pitchfork_env: dict[str, str]
) -> None:
    config = tmp_path / tracked
    config.parent.mkdir(exist_ok=True)
    config.write_text('namespace = "custom"\n[daemons.dev]\nrun = "sleep 60"\n')
    result = register(pitchfork_env, "portfolio-animations", "--dir", str(tmp_path))
    assert result.returncode != 0
    assert "declares namespace" in result.stderr
    assert not (tmp_path / "pitchfork.local.toml").exists()
    assert not calls(pitchfork_env)


def test_register_repairs_missing_slug(
    checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    seed(pitchfork_env, f'[namespaces.app]\ndir = "{checkout}"\n')
    (checkout / "pitchfork.local.toml").write_text('namespace = "app"\n')
    result = register(pitchfork_env, "app", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert calls(pitchfork_env) == [add_call("app", checkout)]
    assert read_config(pitchfork_env)["slugs"] == {
        "app": {"namespace": "app", "daemon": "dev"}
    }


def test_register_uses_hashed_name_on_collision(
    tmp_path: Path, checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    other = tmp_path / "other"
    other.mkdir()
    slug = "skin-groove-intake-" + "x" * 40
    seed(
        pitchfork_env,
        f'[slugs."{slug}"]\nnamespace = "{slug}"\ndaemon = "dev"\n'
        f'[namespaces."{slug}"]\ndir = "{other}"\n',
    )
    results = [register(pitchfork_env, slug, "--dir", str(checkout)) for _ in "12"]
    assert [result.returncode for result in results] == [0, 0], results[0].stderr
    [call] = calls(pitchfork_env)
    name = call[2]
    assert re.fullmatch(f"{slug[:56]}-[0-9a-f]{{6}}", name)
    assert call == add_call(name, checkout)
    assert [result.stdout for result in results] == [f"https://{name}.localhost\n"] * 2
    assert local_namespace(checkout) == name
    config = read_config(pitchfork_env)
    assert config["namespaces"] == {
        slug: {"dir": str(other)},
        name: {"dir": str(checkout)},
    }


def test_register_warns_on_collision(
    tmp_path: Path, checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    other = tmp_path / "other"
    other.mkdir()
    seed(pitchfork_env, f'[namespaces.app]\ndir = "{other}"\n')
    result = register(pitchfork_env, "app", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert "'app' belongs to another checkout" in result.stderr


def test_register_replaces_stale_entry(
    tmp_path: Path, checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    gone = tmp_path / "gone"
    seed(
        pitchfork_env,
        '[slugs.app]\nnamespace = "old"\ndaemon = "dev"\n'
        f'[namespaces.old]\ndir = "{gone}"\n[namespaces.app]\ndir = "{gone}"\n'
        f'[namespaces.keep]\ndir = "{tmp_path}"\n',
    )
    result = register(pitchfork_env, "app", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert result.stderr == ""
    assert calls(pitchfork_env) == [add_call("app", checkout)]
    assert read_config(pitchfork_env) == {
        "slugs": {"app": {"namespace": "app", "daemon": "dev"}},
        "namespaces": {
            "keep": {"dir": str(tmp_path)},
            "app": {"dir": str(checkout)},
        },
    }


def test_remove_deletes_slugs_and_namespaces_of_dir(
    tmp_path: Path, checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    seed(
        pitchfork_env,
        '[slugs.app]\nnamespace = "app"\ndaemon = "dev"\n'
        '[slugs.alias]\nnamespace = "old"\ndaemon = "web"\n'
        '[slugs.main]\nnamespace = "main"\ndaemon = "dev"\n'
        f'[namespaces.app]\ndir = "{checkout}"\n'
        f'[namespaces.old]\ndir = "{checkout}/"\n'
        f'[namespaces.main]\ndir = "{tmp_path}"\n',
    )
    result = register(pitchfork_env, "--remove", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert sorted(calls(pitchfork_env)) == [
        ["proxy", "remove", "alias"],
        ["proxy", "remove", "app"],
    ]
    assert read_config(pitchfork_env) == {
        "slugs": {"main": {"namespace": "main", "daemon": "dev"}},
        "namespaces": {"main": {"dir": str(tmp_path)}},
    }


def test_remove_without_match_exits_zero(
    tmp_path: Path, checkout: Path, pitchfork_env: dict[str, str]
) -> None:
    config = (
        '[slugs.main]\nnamespace = "main"\ndaemon = "dev"\n'
        f'[namespaces.main]\ndir = "{tmp_path}"\n'
    )
    seed(pitchfork_env, config)
    result = register(pitchfork_env, "--remove", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""
    assert not calls(pitchfork_env)
    assert config_path(pitchfork_env).read_text() == config


def test_register_and_remove_with_real_pitchfork(tmp_path: Path) -> None:
    # A mise shim fails under a temporary HOME, because the config files there
    # are not trusted.
    found = subprocess.run(
        ["mise", "which", "pitchfork"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    binary = Path(found.stdout.strip())
    if found.returncode != 0 or not found.stdout.strip():
        pytest.skip("pitchfork is not installed")
    home = tmp_path / "home"
    env = {
        **{k: v for k, v in os.environ.items() if not k.startswith("PITCHFORK_")},
        "PATH": f"{binary.parent}:{os.environ['PATH']}",
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(tmp_path / "xdg-config"),
        "XDG_STATE_HOME": str(tmp_path / "xdg-state"),
    }
    checkout = tmp_path / "app.worktree"
    checkout.mkdir()
    config = home / ".config/pitchfork/config.toml"

    result = register(env, "app.worktree", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    assert result.stdout == "https://app-worktree.localhost\n"
    registered = tomllib.loads(config.read_text())
    assert registered["slugs"] == {
        "app-worktree": {"namespace": "app-worktree", "daemon": "dev"}
    }
    assert registered["namespaces"] == {"app-worktree": {"dir": str(checkout)}}
    assert not (tmp_path / "xdg-config/pitchfork").exists()

    result = register(env, "--remove", "--dir", str(checkout))
    assert result.returncode == 0, result.stderr
    removed = tomllib.loads(config.read_text())
    assert "slugs" not in removed
    assert "namespaces" not in removed


def test_repo_pins_the_global_pitchfork_version() -> None:
    # CI installs only the repo tools, so the real pitchfork test needs this pin.
    tools = tomllib.loads((ROOT / "mise.toml").read_text())["tools"]
    assert tools["pitchfork"] == mise_tools()["pitchfork"]


@pytest.fixture
def modifier(tmp_path: Path) -> tuple[list[str], Path]:
    chezmoi = shutil.which("chezmoi")
    assert chezmoi is not None, "Install the test dependency with: mise install chezmoi"
    source = tmp_path / "source"
    template = source / "dot_config/pitchfork/modify_config.toml"
    template.parent.mkdir(parents=True)
    shutil.copyfile(ROOT / "home/dot_config/pitchfork/modify_config.toml", template)
    shutil.copyfile(ROOT / "home/.chezmoidata.toml", source / ".chezmoidata.toml")
    target = tmp_path / "home/.config/pitchfork/config.toml"
    target.parent.mkdir(parents=True)
    config = tmp_path / "chezmoi.toml"
    config.write_text("")
    command = [
        chezmoi,
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


MANAGED_SETTINGS = {
    "proxy": {
        "enable": True,
        "host": "127.0.0.1",
        "port": 9443,
        "sync_hosts": False,
        "tld": tomllib.loads((ROOT / "home/.chezmoidata.toml").read_text())["proxy"][
            "tld"
        ],
    },
    "supervisor": {"user": pwd.getpwuid(os.getuid()).pw_name},
}


@pytest.mark.parametrize(
    "config",
    [
        "",
        'namespace = "global"\n[daemons.other]\nrun = "keep"\n'
        '[slugs]\napp = {dir = "/app", daemon = "dev"}\n',
        '[settings]\nlog_level = "debug"\n[settings.proxy]\nport = 1\nhttps = false\n',
    ],
)
def test_settings_modifier_preserves_other_configuration(
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
    for table, values in MANAGED_SETTINGS.items():
        for key, value in values.items():
            assert after["settings"][table][key] == value
    for config_table in (before, after):
        settings = config_table.get("settings", {})
        for table, values in MANAGED_SETTINGS.items():
            for key in values:
                settings.get(table, {}).pop(key, None)
            if settings.get(table) == {}:
                del settings[table]
        if settings == {}:
            config_table.pop("settings", None)
    assert after == before
    assert apply(rendered) == rendered


def test_settings_modifier_rejects_invalid_input_without_output(
    modifier: tuple[list[str], Path],
) -> None:
    command, target = modifier
    invalid = '[settings.proxy]\nhost = "unterminated'
    target.write_text(invalid)
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    assert result.returncode != 0
    assert result.stdout == ""
    assert target.read_text() == invalid


def test_pitchfork_setup_starts_supervisor_and_trusts_ca(linux: Shell) -> None:
    result = linux("""
host_has_systemd() { return 0; }
SKIP_MANAGED_TOOLS=false
USER=tester
XDG_STATE_HOME="$HOME/state"
mkdir -p "$XDG_STATE_HOME/pitchfork/proxy"
touch "$XDG_STATE_HOME/pitchfork/proxy/ca.pem"
run_task() { shift; [[ $1 != --sudo ]] || shift; printf '%s\\n' "$*" >> "$HOME/calls"; }
mise() { [[ "$*" == "which pitchfork" ]] && printf 'pitchfork\\n'; }
pitchfork() {
  case "$1 $2" in
  'supervisor status') return 1 ;;
  'proxy status') printf 'Trusted: no\\n' ;;
  esac
}
phase_pitchfork
cat "$HOME/calls"
""")
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.splitlines()[-4:] == [
        "loginctl enable-linger tester",
        "pitchfork boot enable",
        "pitchfork supervisor start",
        "pitchfork proxy trust",
    ]
