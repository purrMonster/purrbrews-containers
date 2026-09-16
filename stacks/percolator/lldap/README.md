# LLDAP

The household's user directory: accounts, passwords and groups. Authelia checks
sign-ins against it; nothing else talks to it directly.

| | |
|---|---|
| Image | `lldap/lldap:v0.6.3` |
| URL | `https://lldap.${DOMAIN}` (own login) |
| Ports | 17170 on 127.0.0.1 only |
| Data | `/srv/data/lldap` (SQLite) |
| Secrets | `LLDAP_ADMIN_PASSWORD`, `LLDAP_JWT_SECRET`, `LLDAP_KEY_SEED` (generated) |

## Accounts and groups

| Name | Kind | Purpose |
|---|---|---|
| `admin` | built-in LLDAP admin | manages the directory; Authelia binds as it |
| `purrbrews_admins` | group | Traefik dashboard, admin in Mealie |
| `purrbrews_household` | group | may sign in to every app |
| `barista` | person | created by `lldap-bootstrap.sh`, in both groups |

Group names come from `.env.local` (`LLDAP_ADMIN_GROUP`, `LLDAP_HOUSEHOLD_GROUP`).
Someone who is in neither group can't sign in to any app.

## Bring up

```bash
./compose.sh lldap up -d
./lldap-bootstrap.sh --dry-run
./lldap-bootstrap.sh              # prints barista's one-time password — keep it
```

## Is it working?

- [ ] `https://lldap.${DOMAIN}` loads; sign in as `admin` with `LLDAP_ADMIN_PASSWORD`
      from `lldap/secrets.env.local`.
- [ ] Groups `purrbrews_admins` and `purrbrews_household` exist, with `barista` in both.
- [ ] Sign in as `barista` with the one-time password and change it
      (top-right menu → *Change password*).
- [ ] Re-running `./lldap-bootstrap.sh` changes nothing.

## Adding people

```bash
./lldap-bootstrap.sh <username>
```

Creates the account in both groups with a random password printed once. Set their
real email in the UI (Authelia sends password-reset links there once a mail notifier
exists), and take them out of `purrbrews_admins` unless they should be an admin.

## Gotchas

- **`LLDAP_LDAP_USER_PASS` only applies to a new database.** To change the admin
  password later, change it in the UI, then put the same value in both
  `lldap/secrets.env.local` (`LLDAP_ADMIN_PASSWORD`) and
  `authelia/secrets.env.local` (`AUTHELIA_LDAP_PASSWORD`), render, and recreate
  Authelia.
- **Losing `LLDAP_KEY_SEED` invalidates every stored password.** It's in the node's
  secrets file; back that up with the data.
- **Break-glass:** if Traefik or Authelia is broken, reach the UI over SSH:
  `ssh -L 17170:127.0.0.1:17170 barista@192.168.0.11`, then `http://localhost:17170`.
- **The web UI is not behind Authelia** on purpose: it would lock you out of fixing
  accounts when Authelia is the thing that's broken. Keep `lldap.` off the tunnel.
