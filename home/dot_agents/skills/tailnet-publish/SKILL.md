---
name: tailnet-publish
description:
  'Share a URL, file, dev server, or decision page with a client over the
  tailnet. Covers Tailscale Serve, Caddy, Pitchfork portless URLs, port
  ownership, impeccable-decision pages, and T3 Code dev servers. Read this
  before a client must load anything served from this VM.'
user-invocable: false
---

# tailnet-publish

Clients load URLs in their own network namespace. Serve every client URL on the
client network (Tailscale or published DNS), never server-side localhost.

## Port ownership

- Caddy terminates TLS on the Tailscale IP at port 443. Caddy proxies to the
  Pitchfork proxy on loopback port 9443.
- Ad-hoc Tailscale Serve publishes set an explicit `--https` port in the
  8443–8499 range, never the default 443.
- Evict a Serve mapping from 443 on sight. Never touch mappings on other ports
  without their owner.

## Share a file

1. Inspect existing Serve mappings with `tailscale serve status`.
2. Start a loopback server for the file.
3. Publish it with
   `tailscale serve --bg --https=8443 --set-path=/<unique-path> <port>`.
4. Read the node DNS name with `tailscale status --json`.
5. Hand over the full HTTPS URL.

## Dev servers (Pitchfork portless URLs)

Portless URLs are `https://<name>.dev.ariaamini.com`.

- Hostnames are single-level. Slugs flatten directory dots to hyphens:
  `app.worktree` serves as `app-worktree`.
- Nested hostnames (`worktree.app.dev…`) do not work. The wildcard certificate
  covers one level.
- Direct `:9443` access does not work. The proxy binds loopback only.
- Register a worktree with
  `pitchfork-register <slug> --daemon dev --dir <workspace-root>`. The helper
  sets the checkout namespace to the slug, for example
  `portfolio-animations/dev`.

## T3 Code dev servers

Use `vp run dev --share`. Do not configure Tailscale Serve by hand.

## Impeccable decision pages

1. Publish with `impeccable-decision serve <payload.json>`.
2. Share the printed tailnet URL.
3. Collect the answer with `impeccable-decision wait`.
4. Tear down with `impeccable-decision down`.

The wrapper handles the engine Host check, the serve port, and the page
lifetime.
