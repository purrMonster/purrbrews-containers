# purrCafe

The household dashboard: home sensors and switches, the month's budget, each
person's own inbox, fleet reachability and a shortcut to every app, plus a
`/wall` view for the kiosk that never sees personal data. Built in its own repo,
[purrMonster/purrCafe](https://github.com/purrMonster/purrCafe); here it's a
published image like any other.

| | |
|---|---|
| Image | `ghcr.io/purrmonster/purrcafe`, pinned in `docker-compose.yml` |
| URL | `https://cafe.${DOMAIN}` — `/wall` for the kiosk |
| Auth | Authelia ForwardAuth: admins + household; the wall group on this host only |
| Data | `/srv/data/purrcafe/data` (encrypted mailboxes, budget cache), `/srv/data/purrcafe/config/home.json` |
| Secrets | `CAFE_APP_ENCRYPTION_KEY` (generated); optional tokens for Home Assistant, Actual and Gatus |

## How it's wired

| Panel | Source | How Café reaches it |
|---|---|---|
| Home | Home Assistant on mochaPot | `http://${MOCHAPOT_LAN_IP}:8123` with a token (like persianPerch) |
| Budget | Actual Budget, here | `http://actualbudget:5006` on `proxy`; read-only |
| Inbox | each person's own IMAP mailbox | `CAFE_MAIL_IMAP_HOST`; each person connects their own in *Settings* |
| Fleet | Gatus on sieve | `https://gatus-api.${DOMAIN}`, Basic auth through Authelia (like persianPerch) |
| Shortcuts | [`services.json`](services.json) | tracked; hostnames only, `admin: true` hides a tile from the household |

Anything not filled in shows "set up" instead of a reading; the app starts with
only the encryption key.

**Who it trusts.** Café reads the user from `Remote-User` / `Remote-Groups`,
which Traefik takes from Authelia and overwrites on every request. It believes
them only from Traefik's own address: [`prepare.sh`](prepare.sh) looks that up
on every `up` and writes `proxy.env.local`. The other apps trust `PROXY_SUBNET`,
but for Café that would let any container on `proxy` sign in as anyone.

## Bring up

```bash
./setup-secrets.sh                 # makes the key; asks for the optional tokens (blank is fine)
./compose.sh purrcafe up -d
```

Then, one panel at a time (each: fill in, `./setup-secrets.sh`, `./compose.sh purrcafe up -d`):

1. **Budget.** Sign in to Actual as its owner. *Settings → Show advanced settings*
   gives the Sync ID; the session token is the `X-ACTUAL-TOKEN` header of any
   `/sync/` request in the browser's network tab. Both go in at the setup prompt.
2. **Home.** In Home Assistant, a **non-admin** user for the dashboard (name it
   after a cat breed), then *Profile → Security → Long-lived access token*.
   Choose entities in `/srv/data/purrcafe/config/home.json` (format:
   [purrCafe's CONFIGURATION.md](https://github.com/purrMonster/purrCafe/blob/main/docs/CONFIGURATION.md#home-assistant)).
   Read-only unless an entity lists `actions`; locks, alarms and covers are always refused.
3. **Fleet.** An LLDAP service account in `perch_api_group` only (a cat breed
   name), then its name and password at the setup prompt. `secrets.hook` builds
   the header.
4. **Wall.** In LLDAP, a group named `CAFE_WALL_GROUP` (`.env.local`) and a
   kiosk account in that group **and nothing else**: any household or admin
   membership gives it personal data. Authelia lets that group into this host only.

## Is it working?

- [ ] `./compose.sh purrcafe ps` shows `healthy`; the `up` printed `trusting Traefik at …/32`.
- [ ] `https://cafe.${DOMAIN}` sends you to Authelia; after sign-in, the overview loads.
- [ ] Each panel you configured shows real data, matching its source app.
- [ ] Settings → connect your mailbox; the inbox lists recent mail.
- [ ] As the wall account: `/wall` loads, and `https://cafe.${DOMAIN}/api/mail` answers 403.
- [ ] As the wall account: any other app (e.g. `homepage.${DOMAIN}`) is refused by Authelia.

## Backups and restore

`backup` takes the whole `/srv/data/purrcafe`; the node backup also carries
`purrcafe/secrets.env.local`. **The key and the data only work together**:
mailboxes saved under one key can't be read with another. Keep a copy of the key
in flask. To undo the app: `./compose.sh purrcafe down` (never `down -v`; the data
is a bind mount anyway).

## Gotchas

- **After recreating Traefik, recreate Café too** (`./compose.sh purrcafe up -d`).
  Traefik's address on `proxy` isn't pinned and can change; until Café is
  re-upped it answers 401 to everyone. Gatus won't notice: Authelia still
  answers in front of it.
- **Rotating the encryption key** disconnects every saved mailbox; each person
  connects theirs again.
- **The Actual session token expires** when that Actual session is signed out.
  The budget panel then says so; paste a fresh one (delete its line from
  `secrets.env.local`, `./setup-secrets.sh`, `up -d`).
