# Caddy credential

Caddy needs one secret: a Cloudflare API token for the wildcard certificate.
Chezmoi stores the token age-encrypted. No secret server is required.

## First setup

Run these steps yourself. Never paste the key or token into chat.
If an age key exists, keep it. If encrypted files exist, restore their key first.

```sh
umask 077
mkdir -p ~/.config/chezmoi ~/.config/personal-secrets
chezmoi age-keygen --output ~/.config/chezmoi/age-key.txt
chezmoi edit-config
```

Back up the private key in LastPass. Merge these settings into the configuration:

```toml
encryption = "age" # Place before all TOML sections.

[age]
identity = "~/.config/chezmoi/age-key.txt"
recipient = "age1..." # Public key from the generated key file.
```

Create `~/.config/personal-secrets/caddy.env` with mode `600` in your editor:

```sh
export CF_API_TOKEN='your-token'
```

The token needs `ariaamini.com` DNS Edit and Zone Read. Then enroll the file:

```sh
chezmoi add --encrypt ~/.config/personal-secrets/caddy.env
```

Chezmoi writes only to the local source state. Commit and push the new `.age` file through the normal jj and PR flow.
Without that push, a new machine cannot restore the token. Enroll the token by hand there instead.

## Change or restore

```sh
chezmoi edit --apply ~/.config/personal-secrets/caddy.env
pitchfork restart global/tls -q
caddy-health
```

On a new machine, run `bootstrap.sh`. It asks for the key when the repository holds encrypted files.
Paste the `AGE-SECRET-KEY-...` line from LastPass. The input stays hidden. Setup then writes the age configuration.
Press Enter to skip. Chezmoi then ignores `~/.config/personal-secrets`. Caddy does not start.

With `--yes` or no terminal, setup cannot ask. Pass the key file instead:

```sh
DOTFILES_AGE_KEY_FILE=/path/to/age-key.txt bash bootstrap.sh --yes
```

Setup never overwrites an existing `chezmoi.toml`. It prints the settings to add.

## Security

The repository holds ciphertext. The applied file and the age key are plaintext on trusted machines.
Processes under your account can read them. Only `caddy-start` loads the token.
Avoid `chezmoi diff`, `chezmoi cat`, and `chezmoi decrypt` in agent sessions.
Old OpenBao role and secret IDs in `~/.config/openbao` stay in place. Revoke or delete them.
