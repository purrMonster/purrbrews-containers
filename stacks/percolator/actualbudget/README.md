# Actual Budget

Envelope budgeting, synced across devices.

| | |
|---|---|
| Image | `actualbudget/actual-server:26.9.0` |
| URL | `https://actualbudget.${DOMAIN}` |
| Data | `/srv/data/actualbudget` (server files and budget files) |
| Secrets | `ACTUALBUDGET_OIDC_CLIENT_SECRET` |

## Decide before the first sign-in

**The first account to sign in becomes the server owner, permanently.** No setting
changes it later. Sign in first as the person who should own the server (normally
`barista`), before sharing the address with anyone.

After that, other household members get an account the first time they sign in with
Authelia (`ACTUAL_USER_CREATION_MODE=login`). The owner shares budgets with them in
*Server settings → User access*.

## Bring up

```bash
./compose.sh actualbudget up -d
./compose.sh actualbudget logs -f
```

## Is it working?

- [ ] Logs show `OpenID configuration found` with no `Error setting up OpenID client`.
- [ ] `https://actualbudget.${DOMAIN}` offers *Sign in with OpenID*, and the owner
      signs in.
- [ ] A budget created on the laptop opens on the phone.

## Gotchas

- **Restarts in a loop until Authelia answers** with a valid certificate: Actual
  checks OpenID discovery at startup. It recovers on its own once Authelia is up.
- **End-to-end encryption** of a budget file (optional, per file) uses a separate
  password that Authelia knows nothing about. Losing it loses the file.
