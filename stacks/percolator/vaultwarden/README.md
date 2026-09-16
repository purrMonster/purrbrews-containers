# Vaultwarden

Password manager, compatible with every Bitwarden app and browser extension.

| | |
|---|---|
| Image | `vaultwarden/server:1.37.2` |
| URL | `https://vault.${DOMAIN}` — admin page at `/admin` |
| Data | `/srv/data/vaultwarden` (SQLite, attachments, icons) |
| Secrets | `VAULTWARDEN_ADMIN_PASSWORD` (type this at `/admin`) and its Argon2id hash `VAULTWARDEN_ADMIN_TOKEN`; `VAULTWARDEN_OIDC_CLIENT_SECRET` |

## Sign-in

- **Two ways in:** email + master password, or *Use single sign-on* with Authelia.
- **The master password still decrypts the vault.** SSO only replaces the account
  login step, so it's asked for after SSO as well.
- **SSO links to an existing account** when the Authelia email matches the Vaultwarden
  account's email. LLDAP emails must therefore be real and unique.

## Bring up

```bash
./compose.sh vaultwarden up -d
```

## First run

1. Create each household member's account at `https://vault.${DOMAIN}` (sign-ups are
   open while `VAULTWARDEN_SIGNUPS_ALLOWED=true`).
2. Close sign-ups: set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in `.env.local`, then
   `./compose.sh vaultwarden up -d`. Later accounts: invite from `/admin` → *Users*.
3. In each client (browser extension, phone app), choose *Self-hosted* and enter
   `https://vault.${DOMAIN}`.

## Is it working?

- [ ] `https://vault.${DOMAIN}` shows the login page with a valid padlock.
- [ ] `/admin` accepts `VAULTWARDEN_ADMIN_PASSWORD` from `vaultwarden/secrets.env.local`.
- [ ] *Use single sign-on* goes to Authelia and back, then asks for the master password.
- [ ] The browser extension syncs; an item added on the phone appears on the laptop.

## Gotchas

- **Bitwarden clients refuse plain HTTP**, so the app is only usable once Traefik's
  certificate is valid and LAN DNS resolves `vault.${DOMAIN}`.
- **The master password is unrecoverable.** Nobody, including the admin page, can
  reset it without losing that person's vault.
- **Export a vault regularly** (*Tools → Export vault*, encrypted JSON) and keep it
  apart from the Google Drive backup chain.
