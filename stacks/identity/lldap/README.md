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

From `nodes/percolator`:

```bash
./compose.sh lldap up -d
../../stacks/identity/lldap/lldap-bootstrap.sh --dry-run
../../stacks/identity/lldap/lldap-bootstrap.sh              # prints barista's one-time password — keep it
```

## Is it working?

- [ ] `https://lldap.${DOMAIN}` loads; sign in as `admin` with `LLDAP_ADMIN_PASSWORD`
      from `lldap/secrets.env.local`.
- [ ] Groups `purrbrews_admins` and `purrbrews_household` exist, with `barista` in both.
- [ ] Sign in as `barista` with the one-time password and change it
      (top-right menu → *Change password*).
- [ ] Re-running `../../stacks/identity/lldap/lldap-bootstrap.sh` changes nothing.

## Adding people

```bash
../../stacks/identity/lldap/lldap-bootstrap.sh <username>
```

Creates the account in both groups with a random password printed once. Set their
real email in the UI (Authelia sends password-reset and 2FA links there, through
`../mail-relay`; LLDAP itself sends no mail, see that README), and take them out of `purrbrews_admins` unless they should be an admin.

## Avatars

Every new LLDAP user gets an avatar when it's created (owner, 2026-11-24).
They live in [`avatars/`](avatars/): `<username>.svg`, the source, and
`<username>.jpg`, the upload (LLDAP takes JPEG only).

- **Bots and service accounts:** an original drawing of the account's cat
  breed with one prop for its job (`scottishfold`, Radicale's read-only reader:
  reading glasses and an open book).
- **People:** ask whether they want one and what of; a photo of their own is
  fine and isn't kept here.

Same style for all of them: flat shapes, no outlines but the prop's, a 512 × 512
SVG with a slate background (`#2f4858`, a `#3e6274` disc), head and shoulders
facing forward. Render it with
`rsvg-convert -w 512 -h 512 <name>.svg -o /tmp/<name>.png && convert /tmp/<name>.png -resize 256x256 -quality 90 -flatten <name>.jpg`
and upload the JPEG on the user's page in the LLDAP UI.

| User | Breed | Prop | Job |
|---|---|---|---|
| `scottishfold` | Scottish Fold | reading glasses, open book | Radicale's LDAP reader (`lldap_strict_readonly`) |

## Gotchas

- **`LLDAP_LDAP_USER_PASS` only applies to a new database.** To change the admin
  password later, change it in the UI, then put the same value in both
  `lldap/secrets.env.local` (`LLDAP_ADMIN_PASSWORD`) and
  `authelia/secrets.env.local` (`AUTHELIA_LDAP_PASSWORD`), render, and recreate
  Authelia.
- **Losing `LLDAP_KEY_SEED` invalidates every stored password.** It's in the node's
  secrets file; back that up with the data.
- **Break-glass:** if Traefik or Authelia is broken, reach the UI over SSH:
  `ssh -L 17170:127.0.0.1:17170 barista@192.168.1.11`, then `http://localhost:17170`.
- **The web UI is not behind Authelia** on purpose: it would lock you out of fixing
  accounts when Authelia is the thing that's broken. Keep `lldap.` off the tunnel.
