---
name: tailnet-publish
description:
  'Share a URL, file, or dev server with a client over the tailnet. Covers
  Tailscale Serve, Caddy, Pitchfork portless URLs, port ownership, and T3 Code
  dev servers. Read this before a client must load anything served from this
  VM.'
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

Portless URLs are `https://<name>.lab.sahandamini.dev`. Caddy serves them with a
public Let's Encrypt certificate, so clients need no CA setup.

- Slugs are single DNS labels. `pitchfork-register` normalizes each slug, so
  `app.worktree` registers `app-worktree`.
- Nested hostnames (`worktree.app.lab…`) do not work. The wildcard certificate
  covers one level.
- Direct `:9443` access does not work. The proxy binds loopback only.
- New worktrees of opted-in repos get a URL automatically, and `wt remove`
  removes it. Register by hand only for a main checkout, with
  `pitchfork-register <slug> --daemon dev --dir <checkout-root>`. The helper
  sets the checkout namespace to the slug, for example `portfolio/dev`.
- A manual `pitchfork-register` exits nonzero on a failure.

## T3 Code dev servers

Use `vp run dev --share`. Do not configure Tailscale Serve by hand.
