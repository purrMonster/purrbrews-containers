# Vikunja

Shared to-do lists, projects and kanban boards.

| | |
|---|---|
| Image | `vikunja/vikunja:2.6.0` |
| URL | `https://vikunja.${DOMAIN}` |
| Data | `/srv/data/vikunja/db` (SQLite), `/srv/data/vikunja/files` (attachments) |
| Secrets | `VIKUNJA_SERVICE_SECRET`, `VIKUNJA_OIDC_CLIENT_SECRET` |

## How it's configured

- **Most settings are environment variables.** The OpenID provider is declared in
  `config/config.yml`, because Vikunja only reads provider settings from the
  environment for providers already named in a file.
- **The client secret comes from the environment**
  (`VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHELIA_CLIENTSECRET`). The rendered file is
  world-readable (the image runs as uid 1000), so it holds no secret.
- **The image runs as uid 1000 and doesn't fix ownership.** `data-dirs` creates its
  directories as `1000:0` before the first start; otherwise it crash-loops on
  "permission denied".
- **Self-registration is off.** Accounts come from Authelia.

## Bring up

```bash
./compose.sh vikunja up -d
```

## Is it working?

- [ ] `https://vikunja.${DOMAIN}` shows *Log in with Authelia*.
- [ ] Signing in creates the account and lands on the home page.
- [ ] `./compose.sh vikunja logs vikunja` has no `OpenID Connect provider 'Authelia'
      not available` after startup.
- [ ] An attachment uploads (proves `files/` is writable).

## Gotchas

- **Provider errors at startup** mean Authelia wasn't reachable with a valid
  certificate when Vikunja started. Restart Vikunja once Authelia is up.
- **Phone apps and CalDAV** use per-user API tokens or passwords set in Vikunja's own
  settings, not Authelia.
