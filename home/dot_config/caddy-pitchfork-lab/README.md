# Caddy + Pitchfork lab

## Live migration 2026-09-28

The experiment graduated to the live setup. Current state:

```text
Client -> Caddy 100.103.205.111:443 -> HTTPS 127.0.0.1:9443 -> Pitchfork -> daemon $PORT
```

- Caddy runs as the Pitchfork daemon `caddy-lab/tls` (`boot_start = true`, `proxy = false`).
  Binary: `~/.local/bin/caddy-cf` (stock 2.11.4 plus `dns.providers.cloudflare`).
  Config: `~/.config/caddy-lab/Caddyfile`; token sourced from `~/.config/caddy-lab/env` (0600).
- The Pitchfork proxy moved from port 443 to 9443 in `~/.config/pitchfork/config.toml`
  (user-level Pitchfork config; not managed by Chezmoi).
- Caddy obtains public wildcard certificates for `*.dev.ariaamini.com` and
  `*.lvh.ariaamini.com` through Cloudflare DNS-01 and renews them automatically.
  Both TLDs now serve portless, publicly trusted URLs.
  Nested worktree routes stay single-label with the `--` encoding, for example
  `web--new-ui--imdbgraph.dev.ariaamini.com`.
- DNS: `*.dev.ariaamini.com A 100.103.205.111` (added); `*.lvh` record already existed.
  `~ariaamini.com` resolves through 1.1.1.1 via
  `/etc/systemd/resolved.conf.d/ariaamini.conf` (Caddy needs SOA answers; the Lima
  host resolver strips them).
- Old URLs keep working: `https://<name>.lvh.ariaamini.com:9443` reaches Pitchfork
  directly. Nested `.lvh` auto-hostnames need that port, because a wildcard
  certificate covers one label only.
- Reboot behavior: the supervisor boots through its user service and starts the
  `boot_start` daemon. Pitchfork 2.21.0 predates the documented `boot_start` key;
  it accepted the config. Verify after the next reboot. Fallback: start Caddy with
  `pitchfork start tls` from `~/.config/caddy-lab`.
- Rollback: stop `caddy-lab/tls`, run
  `pitchfork settings set proxy.port 443 --global`, then
  `pitchfork supervisor start --force`.
- Renewal: Caddy renews both certificates around 2026-11-27. The Cloudflare token in
  `~/.config/caddy-lab/env` must stay valid. The first token appeared in pane
  scrollback and shell history; rotate it and rewrite the file with a hidden prompt.
- Pre-existing, unrelated: `imdbgraph/dev` and `dota-visualizer/dev` both claim
  port 16657, so only one can run at a time.
- Tailscale Serve mappings (ports 8443 to 8446) were not touched. Port 8443 on the
  Tailscale IP belongs to Serve; the Pitchfork proxy binds loopback only.

## Result

Caddy can terminate TLS before Pitchfork without a route entry for each checkout.
Pitchfork retains port allocation, automatic startup, and project/worktree discovery.
The lab passed on 2026-09-28 with Caddy 2.11.4, Pitchfork 2.28.0, and Vite 8.3.1.

Public certificate issuance and client browser trust remain unverified.
Cloudflare DNS authorization is the prerequisite for the selected domain.
Internal TLS still requires client CA trust.

## Layout

The request path is:

```text
HTTPS :18443 -> Caddy -> HTTP 127.0.0.1:18088 -> Pitchfork -> Vite $PORT
```

All experiment listeners bind to loopback.
The runner uses separate Pitchfork config, state, socket, logs, and Caddy storage.
It disables DNS, hosts-file updates, CA installation, the Caddy admin API, and HTTP redirects.
Each run has a private directory under `/tmp/opencode/caddy-pitchfork-lab-*`.

The live Pitchfork binary remains version 2.21.0.
Its process, PID 1279 during this experiment, actually listens on `0.0.0.0:443`.
The live config reports `127.0.0.1`; the listener is the observed runtime state.
The lab does not restart that process.

Existing Tailscale Serve ports were 8443, 8444, 8445, and 8446.
The experiment uses no Serve mapping.
The bootstrap pane reported `no task bootstrap found`; this repository needs no bootstrap task for this lab.

## Hostname rule

One wildcard certificate covers `*.caddy-lab.lvh.ariaamini.com`.
Encode Pitchfork labels in one DNS label, with `--` as the separator:

```text
web--demo.caddy-lab.lvh.ariaamini.com
  -> web.demo.lab.test

web--dotfiles-caddy-pitchfork--dotfiles.caddy-lab.lvh.ariaamini.com
  -> web.dotfiles-caddy-pitchfork.dotfiles.lab.test
```

The Caddyfile contains two generic patterns: project and worktree.
It contains no project-specific routes.
Reserve `--` for separators and keep the complete encoded label within 63 bytes.
Pitchfork normalizes each source label; its namespace must remain unique for each checkout.
The existing jj workspace also has linked-worktree metadata that Pitchfork recognizes.
The runner registers an external configuration for that workspace under the isolated namespace `lab-workspace`.
It creates no additional workspace.

An ordinary `*.lvh.ariaamini.com` certificate cannot cover the nested names above.
Wildcard DNS and wildcard certificate rules differ.
DNS queries for the experiment names currently return `100.103.205.111`.
Cloudflare nameservers are `coby.ns.cloudflare.com` and `braelyn.ns.cloudflare.com`.

## Repeat

Run these commands from this existing jj workspace root.

```bash
mise install caddy@2.11.4 pitchfork@2.28.0
chezmoi --source "$PWD/home" apply "$HOME/.config/caddy-pitchfork-lab"
python3 "$HOME/.config/caddy-pitchfork-lab/experiment.py"
```

The runner requires Python 3.9+, Node compatible with Vite 8, npm, curl, and mise.
The measured Node runtime was 24.21.0.
It downloads pinned Vite and WebSocket packages into its temporary directory.
Its package lock records the resolved transitive versions.
It refuses occupied listeners and a system-level `/etc/pitchfork/config.toml`.
It discards inherited `PITCHFORK_*` overrides.

The runner validates Caddy, registers three stopped daemons, and reserves port 18100.
It then tests project routes, the real workspace route, port allocation, startup, compression, TLS verification, and Vite reload messages.
It stops the lab daemons and proxies after the checks, including on ordinary exceptions.
Logs and `results.json` remain in the printed evidence directory.

## Measured results

Final evidence directory: `/tmp/opencode/caddy-pitchfork-lab-5jdxwmi9`.

- Caddy validation passed.
- All three daemons had null PIDs before proxy access.
- The two project routes returned HTTP 200 from different fixture directories.
- The real workspace route returned HTTP 200 with the correct workspace directory.
- Port 18100 remained occupied; Pitchfork allocated 18101, 18102, and 18103.
- Cold requests took 0.650 s, 0.568 s, and 0.592 s.
- A warm request took 0.043 s.
- After an explicit stop, a request started a new PID in 0.607 s.
- `/@vite/client` used gzip through Caddy.
- A TLS-verified WebSocket connected through both proxies with the `vite-hmr` protocol.
- An HTML file change produced Vite's `full-reload` message for `/index.html`.
- An unknown project returned 404; an invalid hostname format returned 502.
- Explicit trust of the experiment CA passed TLS verification.
- The default system trust store rejected the experiment CA, as expected.

These are single-run measurements, not throughput or latency benchmarks.
The Vite test verifies the reload protocol; it does not verify a browser DOM update or framework module replacement.

## Integration constraints

Pitchfork replaces the forwarded headers before the application receives them:

```text
Host: localhost:18101
X-Forwarded-Host: web.demo.lab.test
X-Forwarded-Proto: http
```

The external HTTPS origin therefore does not reach the application through these standard headers.
Applications that derive redirects, OAuth callbacks, secure cookies, or absolute links from these headers need explicit external-origin configuration.
A general solution needs trusted upstream-header support in Pitchfork.
Test that behavior before a live migration.

Pitchfork's reported URLs and `PITCHFORK_URL` also retain the internal hostname and HTTP port.
This lab tests daemon routes; it does not adapt Pitchfork dashboard links or legacy slugs.
It does not test dependencies, idle shutdown, HTTP/3, or Caddy reload behavior.
Caddy closes WebSockets on config reload by default; `stream_close_delay` can defer that closure.

## Public HTTPS prerequisite

The user selected `ariaamini.com` for this experiment.
The selected lab suffix is `caddy-lab.lvh.ariaamini.com` beneath the existing DNS wildcard.
No DNS token reference was supplied and no DNS record was changed.

For private access with a publicly trusted wildcard certificate:

1. Create a Cloudflare API token with `Zone:DNS:Edit` and `Zone:Zone:Read` for `ariaamini.com` only.
2. Store it in a secret provider or a local Varlock configuration.
3. Supply only its reference or path to the agent.
4. Use a Caddy build with `dns.providers.cloudflare`.
5. Verify that the wildcard DNS record resolves to this VM's Tailscale address from the client.
6. Bind Caddy to the Tailscale address on a spare port for the client test.
7. Replace `tls internal` with the DNS issuer configuration below.
8. Test ACME staging before production issuance.
9. Test a client browser without certificate bypass flags.

```caddyfile
tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
}
```

The stock mise Caddy package does not include the Cloudflare DNS module.
Use Varlock to inject the token at runtime; do not place it in the Caddyfile or command arguments.
DNS-01 requires no public inbound listener.
ACME staging certificates are not publicly trusted; production issuance is necessary for the final browser test.
Certificate renewal requires persistent Caddy storage and continued DNS authorization.

## Client browser status

The Mac was online at `100.76.254.68`.
Its CDP port 9222 timed out over Tailscale and refused a connection at the Lima host address `192.168.5.2`.
Client trust could not be tested.

On the Mac, start a separate Chrome profile:

```bash
open -na "Google Chrome" --args \
  --remote-debugging-address=0.0.0.0 \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/axi-caddy-lab
```

Chrome can require an SSH tunnel for remote CDP access.
Use the browser skills to verify access before a client test.
A future client test needs a live Caddy listener on the Tailscale interface.
The current loopback-only run ends automatically and supplies no client URL.

## Cleanup

The completed run stopped all experiment processes.
The live Dota Visualizer route still returned HTTP 200 after the tests.

For an interrupted run, substitute its printed evidence path below:

```bash
lab=/tmp/opencode/caddy-pitchfork-lab-5jdxwmi9
export PITCHFORK_CONFIG_DIR="$lab/pitchfork"
export PITCHFORK_STATE_DIR="$lab/state"
mise exec pitchfork@2.28.0 -- pitchfork stop demo/web feature-demo/web lab-workspace/web
mise exec pitchfork@2.28.0 -- pitchfork supervisor stop
unset PITCHFORK_CONFIG_DIR PITCHFORK_STATE_DIR
ss -ltnp '( sport = :18443 or sport = :18088 or sport = :18101 or sport = :18102 or sport = :18103 )'
```

If Caddy remains, identify the PID whose command uses `$lab/Caddyfile`, then send that PID `SIGTERM`.
After all lab processes stop, delete that exact evidence directory if no longer needed.

```bash
rm -rf -- "$lab"
```

The evidence directory includes the temporary CA key; do not publish the entire directory.
The experiment installed no CA trust, boot service, DNS override, or Serve mapping that requires removal.
The Chezmoi target contains only the repeatable lab files.
Keep the installed tool versions for repeat runs; neither version was activated globally.

## Sources

- https://pitchfork.jdx.dev/guides/port-management
- https://caddyserver.com/docs/automatic-https
- https://caddyserver.com/docs/caddyfile/directives/reverse_proxy
- https://github.com/caddy-dns/cloudflare
