# Vaultwarden

Password manager, compatible with every Bitwarden app and browser extension.

| | |
|---|---|
| Image | `vaultwarden/server:1.37.2` |
| URL | `https://vault.${DOMAIN}` — admin page at `/admin` |
| Data | `/srv/data/vaultwarden` (SQLite, attachments, icons) |
| Secrets | `VAULTWARDEN_ADMIN_PASSWORD` (type this at `/admin`) and its Argon2id hash `VAULTWARDEN_ADMIN_TOKEN`; `VAULTWARDEN_OIDC_CLIENT_SECRET` |

## Sign-in

- **SSO-only (set 2026-09-17):** `SSO_ONLY=true` means the only way in is
  *Use single sign-on* with Authelia — plain email+master-password login is
  refused outright. Every household member authenticates via Authelia first.
- **The master password still decrypts the vault, and always will.**
  Vaultwarden has no equivalent of Bitwarden Enterprise's Key Connector, so
  there's no way to remove this prompt — it's the client-side encryption
  key for the vault, never sent to or seen by the server, so no login
  method (SSO included) can substitute for it. It's asked for immediately
  after the Authelia round-trip. "OIDC only" here means OIDC-only
  *authentication*, not a passwordless vault — the latter isn't something
  Vaultwarden supports (confirmed 2026-09-17, see Gotchas below).
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
- [ ] The plain email+master-password login form no longer works (SSO_ONLY=true) —
      confirm this deliberately, since it locks out anyone who doesn't have an
      Authelia account yet.
- [ ] The browser extension syncs; an item added on the phone appears on the laptop.

## Gotchas

- **"OIDC only" can't mean passwordless.** Vaultwarden's master password is the
  vault's client-side encryption key, not just a login credential — the server
  never sees it and can't decrypt anything without it, so no SSO provider can
  replace it. Bitwarden Enterprise's Key Connector is the only mechanism that
  removes this prompt, and Vaultwarden doesn't implement it (checked 2026-09-17
  against [dani-garcia/vaultwarden discussion #6678](https://github.com/dani-garcia/vaultwarden/discussions/6678)).
  `SSO_ONLY=true` is as close as it gets: it removes the *other* login door
  (plain email+password against Vaultwarden itself), so Authelia becomes
  mandatory, but the master password step after it is permanent.
- **SSO_ONLY locks out anyone without an Authelia account.** There's no local
  fallback once it's on — unlike Home Assistant/Paperless/Nextcloud, which all
  keep a native-login break-glass path, Vaultwarden's own login form is now
  refused entirely. If Authelia is ever down, nobody gets into Vaultwarden
  either, admin included (the `/admin` page is separate — `ADMIN_TOKEN` still
  works — but that only manages the instance, not any individual vault).
- **Bitwarden clients refuse plain HTTP**, so the app is only usable once Traefik's
  certificate is valid and LAN DNS resolves `vault.${DOMAIN}`.
- **The master password is unrecoverable.** Nobody, including the admin page, can
  reset it without losing that person's vault.
- **Export a vault regularly** (*Tools → Export vault*, encrypted JSON) and keep it
  apart from the Google Drive backup chain.
