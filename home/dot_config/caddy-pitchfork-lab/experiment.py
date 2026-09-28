#!/usr/bin/env python3
"""Run an isolated lab, then stop every lab process. Retain evidence in /tmp/opencode."""

import http.client
import json
import os
from pathlib import Path
import shutil
import shlex
import socket
import ssl
import subprocess
import tempfile
import time


SOURCE = Path(__file__).resolve().parent
WORKSPACE = Path.cwd()
ROOT = Path(tempfile.mkdtemp(prefix="caddy-pitchfork-lab-", dir="/tmp/opencode"))
ENV = {
    key: value for key, value in os.environ.items() if not key.startswith("PITCHFORK_")
} | {
    "PITCHFORK_CONFIG_DIR": str(ROOT / "pitchfork"),
    "PITCHFORK_STATE_DIR": str(ROOT / "state"),
    "XDG_DATA_HOME": str(ROOT / "data"),
    "XDG_CONFIG_HOME": str(ROOT / "config"),
}


def tool(name, version):
    return subprocess.check_output(
        ["mise", "exec", f"{name}@{version}", "--", "which", name], text=True
    ).strip()


PF = [tool("pitchfork", "2.28.0")]
CADDY = [tool("caddy", "2.11.4")]
HOST = "web--demo.caddy-lab.lvh.ariaamini.com"
CA = ROOT / "data/caddy/pki/authorities/local/root.crt"


def run(command, **kwargs):
    try:
        return subprocess.run(command, cwd=ROOT, env=ENV, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr)
        raise


def request(host=HOST, path="/__lab", context=None):
    # Keep DNS and trust stores unchanged; preserve the real TLS server name.
    class LoopbackHTTPSConnection(http.client.HTTPSConnection):
        def connect(self):
            raw = socket.create_connection(("127.0.0.1", 18443), 40)
            self.sock = (context or ssl.create_default_context()).wrap_socket(
                raw, server_hostname=host
            )

    connection = LoopbackHTTPSConnection(host, 18443, timeout=40)
    started = time.monotonic()
    try:
        connection.request("GET", path)
        response = connection.getresponse()
        return (
            response.status,
            response.read().decode(),
            round(time.monotonic() - started, 3),
        )
    finally:
        connection.close()


def wait_port(port, process):
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError(f"Process exited: {process.args}; inspect {ROOT}")
        try:
            with socket.create_connection(("127.0.0.1", port), 0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError(f"Port {port}")


processes = []
results = {
    "runtime": str(ROOT),
    "versions": {"caddy": "2.11.4", "pitchfork": "2.28.0", "vite": "8.3.1"},
}
print(f"Evidence: {ROOT}", flush=True)
try:
    if Path("/etc/pitchfork/config.toml").exists():
        raise RuntimeError(
            "System Pitchfork config exists; review isolation before this lab"
        )
    for port in (18088, 18443, 18100, 18101, 18102, 18103):
        with socket.socket() as probe:
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            probe.bind(("127.0.0.1", port))
    shutil.copytree(SOURCE / "pitchfork", ROOT / "pitchfork")
    for name in ("server.mjs", "check-hmr.mjs", "Caddyfile"):
        shutil.copy2(SOURCE / name, ROOT / name)
    run(
        [
            "npm",
            "install",
            "--no-audit",
            "--no-fund",
            "--prefix",
            str(ROOT),
            "vite@8.3.1",
            "ws@8.18.3",
        ]
    )
    for name in ("demo", "feature-demo"):
        project = ROOT / name
        project.mkdir()
        (project / "index.html").write_text(
            f"<!doctype html><title>{name}</title><h1>{name}</h1>\n"
        )
        shutil.copy2(SOURCE / "project.toml", project / "pitchfork.toml")
        run(
            PF
            + [
                "config",
                "add",
                str(project / "pitchfork.toml"),
                "--dir",
                str(project),
                "--namespace",
                name,
            ]
        )
    if not (WORKSPACE / ".jj").exists():
        raise RuntimeError("Run this experiment from the existing jj workspace root")
    workspace_config = ROOT / "workspace.toml"
    workspace_config.write_text(
        "[daemons.web]\n"
        + "run = "
        + json.dumps(
            f"LAB_FIXTURE={shlex.quote(str(ROOT / 'demo'))} node {shlex.quote(str(ROOT / 'server.mjs'))}"
        )
        + "\n"
        + "port = { expect = [18100], bump = 10 }\n"
        + 'ready_cmd = "curl -fsS http://127.0.0.1:$PORT/__lab"\n'
    )
    run(
        PF
        + [
            "config",
            "add",
            str(workspace_config),
            "--dir",
            str(WORKSPACE),
            "--namespace",
            "lab-workspace",
        ]
    )
    results["routes"] = json.loads(
        run(PF + ["proxy", "status", "--json"], capture_output=True, text=True).stdout
    )
    run(CADDY + ["validate", "--config", str(ROOT / "Caddyfile")])
    for command, logname, port in (
        (PF + ["supervisor", "run"], "pitchfork.log", 18088),
        (CADDY + ["run", "--config", str(ROOT / "Caddyfile")], "caddy.log", 18443),
    ):
        with (ROOT / logname).open("w") as log:
            process = subprocess.Popen(
                command, cwd=ROOT, env=ENV, stdout=log, stderr=subprocess.STDOUT
            )
        processes.append(process)
        wait_port(port, process)
    for _ in range(100):
        if CA.exists():
            break
        time.sleep(0.1)
    context = ssl.create_default_context(cafile=str(CA))
    results["before"] = json.loads(
        run(PF + ["list", "--json"], capture_output=True, text=True).stdout
    )
    assert all(item["pid"] is None for item in results["before"])
    with socket.socket() as occupied:
        occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        occupied.bind(("127.0.0.1", 18100))
        occupied.listen()
        for name in ("demo", "feature-demo"):
            host = f"web--{name}.caddy-lab.lvh.ariaamini.com"
            status, body, elapsed = request(host, context=context)
            assert status == 200, (status, body)
            observed = json.loads(body)
            assert observed["cwd"] == str(ROOT / name), observed
            assert observed["port"] != 18100, observed
            assert observed["forwardedHost"] == f"web.{name}.lab.test", observed
            results[name] = observed | {"cold_seconds": elapsed}
        assert results["demo"]["port"] != results["feature-demo"]["port"]
        workspace_route = next(
            daemon["host"]
            for project in results["routes"]["projects"]
            for worktree in project.get("worktrees", [])
            if worktree["dir"] == str(WORKSPACE)
            for daemon in worktree["daemons"]
            if daemon["daemon"] == "web"
        )
        workspace_host = (
            workspace_route.replace(".", "--") + ".caddy-lab.lvh.ariaamini.com"
        )
        assert len(workspace_host.split(".")[0]) <= 63
        status, body, elapsed = request(workspace_host, context=context)
        assert status == 200, (status, body)
        observed = json.loads(body)
        assert observed["cwd"] == str(WORKSPACE), observed
        assert observed["port"] not in (
            18100,
            results["demo"]["port"],
            results["feature-demo"]["port"],
        )
        results["worktree"] = observed | {
            "hostname": workspace_host,
            "cold_seconds": elapsed,
        }
        status, _, elapsed = request(context=context)
        assert status == 200
        results["warm_seconds"] = elapsed
        headers = run(
            [
                "curl",
                "--noproxy",
                "*",
                "--cacert",
                str(CA),
                "--resolve",
                f"{HOST}:18443:127.0.0.1",
                "-sS",
                "-D",
                "-",
                "-o",
                "/dev/null",
                "-H",
                "Accept-Encoding: gzip",
                f"https://{HOST}:18443/@vite/client",
            ],
            capture_output=True,
            text=True,
        ).stdout
        assert "content-encoding: gzip" in headers.lower(), headers
        results["compression"] = "gzip"
        results["hmr"] = json.loads(
            run(
                ["node", "check-hmr.mjs", str(CA), str(ROOT / "demo/index.html")],
                capture_output=True,
                text=True,
            ).stdout
        )
        run(PF + ["stop", "demo/web"])
        status, body, elapsed = request(context=context)
        assert status == 200, body
        restarted = json.loads(body)
        assert restarted["pid"] != results["demo"]["pid"]
        results["restart"] = restarted | {"seconds": elapsed}
    for name, host in (
        ("unknown", "web--absent.caddy-lab.lvh.ariaamini.com"),
        ("malformed", "bad.caddy-lab.lvh.ariaamini.com"),
    ):
        status, _, _ = request(host, context=context)
        assert status >= 400, status
        results[name] = status
    try:
        request()
        results["system_trust"] = "trusted"
    except ssl.SSLCertVerificationError:
        results["system_trust"] = "untrusted (expected; no CA installed)"
    results["after"] = json.loads(
        run(PF + ["list", "--json"], capture_output=True, text=True).stdout
    )
finally:
    if processes:
        for args in (
            ["stop", "demo/web", "feature-demo/web", "lab-workspace/web"],
            ["supervisor", "stop"],
        ):
            try:
                subprocess.run(PF + args, cwd=ROOT, env=ENV, timeout=30, check=True)
            except (subprocess.SubprocessError, OSError) as error:
                results.setdefault("cleanup_errors", []).append(str(error))
    for process in reversed(processes):
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    (ROOT / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
