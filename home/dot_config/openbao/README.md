# Caddy HTTPS

Pitchfork supervises OpenBao Agent, which starts Caddy with the Cloudflare token in its environment.
Caddy serves `*.dev.ariaamini.com` on the Tailscale address and forwards requests to Pitchfork on loopback port 9443.
Mise installs the pinned Caddy build with the Cloudflare DNS module.

`caddy-start` waits for the Tailscale interface and supplies its address through `CADDY_BIND`.
Agent uses AppRole, renews its token, and checks the Cloudflare secret every five minutes.
Agent restarts Caddy when the secret changes.
The Cloudflare token stays in memory; Caddy configuration autosave is disabled.
`caddy-health` checks HTTPS without a development app or a public DNS lookup.

## Server enrollment

The installer configures Pitchfork on loopback.
An administrator must enroll each server separately.
Point the development DNS wildcard at the server's Tailscale address.
Authenticate Tailscale before Caddy starts.

Apply the dotfiles and install the tools before enrollment:

```sh
sudo apt-get install libcap2-bin procps
mise install http:caddy-cf aqua:openbao/openbao/bao
```

If the kernel restricts port 443, the Caddy install hook uses `sudo setcap` to grant `CAP_NET_BIND_SERVICE`.
The hook runs after Caddy installation or replacement, including upgrades.
It targets the installed Caddy executable, not the Mise shim.

If Caddy was installed before this hook, grant the capability once:

```sh
sudo setcap cap_net_bind_service=+ep "$(mise which caddy-cf)"
```

Log in with an administrator token at the hidden prompt:

```sh
export BAO_ADDR=https://vault.ariaamini.com
bao login -no-print
bao secrets list -detailed
bao auth list
```

Confirm that `kv/` uses KV v2.
If `approle/` is absent, enable it:

```sh
bao auth enable approle
```

Apply the read-only policy and role:

```sh
bao policy write caddy-reader ~/.config/openbao/policies/caddy-reader.hcl
bao write auth/approle/role/caddy-lab @"$HOME/.config/openbao/caddy-role.json"
```

Create the unmanaged machine credentials on a new server:

```sh
umask 077
bao read -field=role_id auth/approle/role/caddy-lab/role-id > ~/.config/openbao/caddy-role-id.new &&
bao write -f -field=secret_id auth/approle/role/caddy-lab/secret-id > ~/.config/openbao/caddy-secret-id.new &&
chmod 600 ~/.config/openbao/caddy-role-id.new ~/.config/openbao/caddy-secret-id.new &&
mv ~/.config/openbao/caddy-role-id.new ~/.config/openbao/caddy-role-id &&
mv ~/.config/openbao/caddy-secret-id.new ~/.config/openbao/caddy-secret-id
```

The SecretID has no expiry or use limit, so Agent can authenticate after a reboot.
The role issues one-hour tokens with a four-hour maximum lifetime.
Revoke the SecretID through its accessor when you replace or retire the server identity.
Keep both credential files outside Chezmoi and version control.

## Cloudflare token

Restrict the Cloudflare API token to the `ariaamini.com` zone.
Grant `Zone / DNS / Edit` and `Zone / Zone / Read`.
Store `CF_API_TOKEN` at `kv/personal-keyring/caddy-lab`.

For a new secret, use hidden input and a create-only write:

```sh
bash -c 'set -euo pipefail; read -rsp "Cloudflare API token: " token; printf "\n" >&2; test -n "$token"; printf %s "$token" | bao kv put -mount=kv -cas=0 personal-keyring/caddy-lab CF_API_TOKEN=-'
```

For rotation, preserve other fields with a patch:

```sh
bash -c 'set -euo pipefail; read -rsp "New Cloudflare API token: " token; printf "\n" >&2; test -n "$token"; printf %s "$token" | bao kv patch -mount=kv personal-keyring/caddy-lab CF_API_TOKEN=-'
```

Start Caddy, or restart it for an immediate token update:

```sh
pitchfork restart global/tls -q
caddy-health
```

After HTTPS works, revoke the previous Cloudflare token.
Remove the legacy `CF_API_TOKEN` entry from `~/.config/caddy-lab/.env.local` yourself.
Preserve unrelated values.
