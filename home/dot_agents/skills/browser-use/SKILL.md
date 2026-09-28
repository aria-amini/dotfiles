---
name: browser-use
description:
  'Guidance for using chrome-devtools-axi to debug with a real browser.
  Covers where the browser runs (client over CDP, or headless on the server),
  connection setup, certificate trust, endpoint switching, and the CLI
  workflow: navigate, snapshot, click, fill forms, run JavaScript, inspect
  console and network, take screenshots, audit performance. Read this first
  for any task that needs a real browser.'
user-invocable: false
---

# browser-use

Driver: `chrome-devtools-axi` (wraps chrome-devtools-mcp). Run it as
`npx -y chrome-devtools-axi <command>`; no global install needed. The first
command auto-starts a persistent bridge, so the browser session survives
across invocations. Run `stop` when you finish.

## When to use

Use a real browser when a task needs one: opening or testing a page, clicking
through a flow, filling forms, extracting page content, debugging console
errors or network requests, screenshots, performance audits. Skip it when
plain `fetch`/`curl` suffices; static pages and simple extraction do not
justify the Chrome cold-start.

## Where the browser runs

Browser automation prefers Chrome on the client over CDP. Detect the online
client with `tailscale status`. Ask the user to start Chrome with remote
debugging when no client browser runs. Use the server headless browser only
when no client is reachable: client offline, CI, or batch captures.

### Connect to a client browser

1. Detect the online client with `tailscale status`. Ask the user to start
   Chrome on that client with remote debugging and a temp profile. Chrome
   rejects debugging on the default profile. Per-client commands: platform
   notes.
2. Connect:

   ```bash
   CHROME_DEVTOOLS_AXI_BROWSER_URL=http://<client-ip>:9222 \
     npx -y chrome-devtools-axi open <page-url>
   ```

A reachable CDP endpoint does not prove the page URL loads on the client.
Verify both paths.

Chrome reuses a running instance per profile and drops new launch flags. Quit
the old instance fully before relaunch. Verify with a page that failed before.

The page URL runs in the client browser's network namespace. Serve pages the
client must load on the client network (Tailscale or published DNS), never
server-side localhost. If navigation times out, verify the page URL from the
client network independently.

### Certificates

The private CA (Pitchfork Local CA for `*.lvh.ariaamini.com`) lives on the
server. Fresh client profiles reject it. In order:

1. Durable: trust `ca.pem` on the client. Server-side `pitchfork proxy trust`
   covers the server store only.
2. One-off debug: relaunch the client Chrome with `--ignore-certificate-errors`.

### Platform notes

#### macOS client

- Start Chrome:

  ```bash
  open -na "Google Chrome" --args \
    --remote-debugging-address=0.0.0.0 \
    --remote-debugging-port=9222 \
    --user-data-dir=/tmp/axi-chrome
  ```

- Trust the CA: import the server's `ca.pem`
  (`~/.local/state/pitchfork/proxy/ca.pem`) into the login keychain with trust
  flags.
- Lima guests reach the Mac at the IP from `getent hosts host.lima.internal`.
  Chrome rejects the `host.lima.internal` Host header. Use the IP.

#### Windows client

- Start Chrome:

  ```bat
  start chrome --remote-debugging-port=9222 --user-data-dir=%TEMP%\axi-chrome
  ```

- Non-headless Chrome on Windows listens on `127.0.0.1` only.
  `--remote-debugging-address` is not reliable there. Forward the port:

  ```bat
  netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=9222 connectaddress=127.0.0.1 connectport=9222
  ```

- Allow port 9222 in Windows Firewall when it prompts.
- Trust the CA: `certutil -addstore -user Root ca.pem`.
- Verify reachability from the VM:
  `curl -s http://<client-ip>:9222/json/version`. If it fails, use the server
  fallback.

### Server fallback

Install full Chromium once with `npx playwright install chromium`.

Never use `chrome-headless-shell` with axi. axi cannot select pages in the old
headless shell. `open`, `newpage`, and `selectpage` hang or fail with
"No page is currently selected". Use the full build with `--headless=new`.

The binary path differs by architecture: `chrome-linux/chrome` on x64,
`chrome-linux-arm64/chrome` on arm64.

Chromium reads NSS, not `/etc/ssl`, so pass `--ignore-certificate-errors` for
private-CA domains even when `curl` verifies cleanly.

```bash
setsid nohup ~/.cache/ms-playwright/chromium-*/chrome-linux*/chrome \
  --headless=new --no-sandbox --ignore-certificate-errors \
  --remote-debugging-address=127.0.0.1 --remote-debugging-port=9333 \
  --user-data-dir=/tmp/axi-chrome-vm --no-first-run \
  about:blank >/tmp/chromium.log 2>&1 < /dev/null &
disown
```

Set `CHROME_DEVTOOLS_AXI_BROWSER_URL` on every axi command. Without it, axi
tries to launch its own Chrome and fails with `BRIDGE_NOT_READY`.

```bash
export CHROME_DEVTOOLS_AXI_BROWSER_URL=http://127.0.0.1:9333
```

## Playwright captures (server)

Use the Playwright library for batch screenshots, not axi. Import engines from
`@playwright/test`. pnpm strict layouts hide the `playwright` package.
`NODE_PATH` does not work for ESM imports. Anchor a require at the project:

```js
import { createRequire } from 'module'
const require = createRequire('/path/to/project/package.json')
const { chromium, firefox } = require('@playwright/test')
```

Rules from live captures:

- Pass `ignoreHTTPSErrors: true` on `newContext` for `*.lvh.ariaamini.com`.
  Firefox keeps certificates in its own NSS store. Without the flag, it
  renders the Pitchfork CA error page.
- Validate captures with `md5sum`. Identical hashes across pages mean every
  file shows the same error page, not the app.
- Force a theme with `ctx.addCookies` before `goto`. Pass
  `colorScheme: 'dark'` for `prefers-color-scheme` fallbacks.
- Headless Chromium can crash ("page crashed") on heavy sites. First try
  `args: ['--disable-dev-shm-usage', '--disable-gpu', '--no-sandbox']`.
  If the crash survives, use Playwright Firefox. Firefox captures sites
  that crash Chromium.
- Chromium `--screenshot` with `--virtual-time-budget` hangs on live dev
  servers (websockets). Skip the CLI for app captures; use the library.
- Chromium returns blank `fullPage` shots of very tall pages. Firefox
  handles them.

## Endpoint and session pitfalls

- The axi bridge fixes its connection mode at startup. Run
  `npx -y chrome-devtools-axi stop` before switching browsers. After reconnect,
  run `pages`, then `selectpage <id>`.
- Verified flow: `open <url>` navigates, selects the page, and returns the
  snapshot. When a command reports "No page is currently selected", run
  `pages`, then `selectpage <id>`.
- Kill browser processes by exact name or by PID. A `pkill -f` pattern that
  appears in the invoking shell command line kills that shell.

## Workflow

1. Run `npx -y chrome-devtools-axi open <url>` to navigate. Output includes
   the page's accessibility snapshot; interactive elements carry `uid=` refs.
2. Interact by ref: `click @<uid>`, `fill @<uid> <text>`,
   `fillform @<uid>=<val>...`, `hover @<uid>`, `drag @<from> @<to>`,
   `upload @<uid> <path>`.
3. Pass refs back exactly as printed, including the `g<N>:` generation prefix.
   If the page re-rendered since the snapshot, the action fails loudly with
   `STALE_REF`; run `snapshot` again and retry with fresh refs.
4. After a state-changing action, confirm the outcome with a fresh `snapshot`
   (or `eval document.title` / `screenshot <path>`) before reporting success.
   A valid-ref click can still silently no-op, and `STALE_REF` only catches
   stale refs.
5. Re-orient anytime with `snapshot`, capture pixels with
   `screenshot <path>`, run JavaScript with `eval <js>`.
6. Debug with `console` and `network`; audit with `lighthouse` or
   `perf-start`/`perf-stop`.
7. Every response ends with contextual next-step hints. Follow them.

## Commands

Run `npx -y chrome-devtools-axi --help` for the command list, and
`npx -y chrome-devtools-axi <command> --help` for per-command flags and
environment variables.

## Tips

- Pipe output through grep/head to extract specific data from large pages.
- Add `--full` to snapshot-producing commands to disable truncation.
- Save large request/response bodies to files with
  `network-get <id> --response-file <path>` (or `--request-file`) instead of
  dumping them into chat.
- Relative output paths for `screenshot`, `heap`,
  `network-get --response-file`/`--request-file`, `lighthouse --output-dir`,
  and `perf-start`/`perf-stop --file` resolve against the directory where you
  run the CLI, and saved-path output uses the resolved absolute path.
