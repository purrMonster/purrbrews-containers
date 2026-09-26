# Authelia

Single sign-on. Every app signs people in with Authelia over OpenID Connect, and
pages without a login of their own sit behind its ForwardAuth: Homepage and the
Traefik dashboard here, and the admin UIs on other nodes. Accounts come from LLDAP.

| | |
|---|---|
| Images | `authelia/authelia:4.39.27`, `redis:8.8.2-alpine` (sessions, private) |
| URL | `https://authelia.${DOMAIN}` |
| Ports | `9091`, UFW-limited to `FORWARD_AUTH_CLIENTS` (other nodes' Traefik) |
| Data | `/srv/data/authelia/data` (SQLite: 2FA devices, consents), `/srv/data/authelia/redis` |
| Secrets | all generated: session, storage, reset-JWT, OIDC HMAC and signing key, Redis password, one hashed client secret per app |

## Who can sign in to what

- **Any app:** members of `purrbrews_admins` or `purrbrews_household`. Anyone else
  is refused by Authelia before the app ever sees them (`household` policy).
- **Admin pages:** `purrbrews_admins` only: `traefik`, `traefik-sieve`, `pihole`,
  `netalertx`, `gatus`. The list is the first rule in the config template, followed
  by a `deny` for the same hosts: Authelia skips a rule whose subject doesn't match,
  so without it the household catch-all would let everyone in.
- **Pages behind ForwardAuth** that aren't on that list (Homepage): admins + household.
- **Level:** `AUTH_POLICY` in `.env.local`, `one_factor` to start. After every
  household member has enrolled a second factor, set it to `two_factor`, render, and
  recreate Authelia. Switching earlier locks out whoever hasn't enrolled.

## OIDC clients

| Client ID | App | Token auth | PKCE |
|---|---|---|---|
| `nextcloud` | Nextcloud (user_oidc app) | `client_secret_post` | yes |
| `immich` | Immich | `client_secret_basic` | yes |
| `paperless` | Paperless-ngx | `client_secret_basic` | yes |
| `vaultwarden` | Vaultwarden | `client_secret_basic` | yes |
| `mealie` | Mealie | `client_secret_basic` | yes |
| `vikunja` | Vikunja | `client_secret_basic` | no (unsupported) |
| `actual-budget` | Actual Budget | `client_secret_basic` | no |
| `freshrss` | FreshRSS | `client_secret_basic` | no |

Each app's `secrets.conf` generates its plaintext secret, and
`authelia/secrets.conf` hashes it (PBKDF2) into `authelia/secrets.env.local` in the
same `./setup-secrets.sh` run, so the two can't drift apart. Adding a client is a
line in each of those two files plus its block in the template.

## Bring up

After LLDAP and `./lldap-bootstrap.sh`:

```bash
./compose.sh authelia up -d
sudo docker logs -f authelia
```

## Is it working?

- [ ] Logs end with `Startup complete`; no LDAP errors.
- [ ] `https://authelia.${DOMAIN}/.well-known/openid-configuration` returns JSON
      with `"issuer": "https://authelia.${DOMAIN}"`.
- [ ] Sign in at `https://authelia.${DOMAIN}` as `barista`.
- [ ] `https://traefik.${DOMAIN}` opens the dashboard after signing in.
- [ ] From sieve: `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.0.11:9091/api/health`
      gives `200`, and from a LAN laptop the same command times out.
- [ ] From a LAN laptop, `https://pihole.${DOMAIN}` redirects to Authelia and opens
      after signing in as an admin.
- [ ] Enrol a second factor (*Settings → Two-Factor Authentication*). With no mail
      server, the confirmation code is in `/srv/data/authelia/data/notification.txt`:
      `sudo tail /srv/data/authelia/data/notification.txt`.

Checking one client's secret without a browser (expect `invalid_grant`; `invalid_client`
means the secret or auth method is wrong):

```bash
S=$(grep ^MEALIE_OIDC_CLIENT_SECRET= mealie/secrets.env.local | cut -d= -f2)
curl -s https://authelia.${DOMAIN}/api/oidc/token -u "mealie:$S" \
  -d grant_type=authorization_code -d code=x -d redirect_uri=https://x/ | jq -r .error
```

## Gotchas

- **After any change to its config or secrets:** `./render-configs.sh`, then
  `./compose.sh authelia up -d --force-recreate`. The rendered file is bind-mounted,
  so a plain `up -d` may keep the old container.
- **Generate client secrets with the script, not by hand.** They are hex because
  base64's `+ / =` make `client_secret_basic` fail in apps that don't URL-encode
  the secret, even though both sides hold the identical string.
- **`notification.txt` is the mailbox** until an SMTP notifier is configured:
  password-reset and device-enrolment links land there.
- **Losing `AUTHELIA_STORAGE_ENCRYPTION_KEY` makes the database unreadable** (all
  enrolled 2FA devices are lost). Back it up with the node's secrets.
## Other nodes: the published port

Every node runs its own Traefik. Their ForwardAuth middleware calls
`http://192.168.0.11:9091/api/authz/forward-auth` directly:

- **Why not through percolator's Traefik:** it treats the call as an ordinary request
  and rewrites `X-Forwarded-Method/Host/Uri`, so Authelia answers `400`.
- **Why it's safe:** `firewall.sh` opens 9091 only to the IPs in
  `FORWARD_AUTH_CLIENTS`. The port is plain HTTP and also serves the login portal, so
  it must never be opened to the LAN. People always sign in through
  `https://authelia.${DOMAIN}`.
- **The session is shared:** the cookie is for `${DOMAIN}`, so signing in once
  covers every node.

**Adding a node's Traefik:** add its IP to `FORWARD_AUTH_CLIENTS` in `.env.local`,
`sudo ./firewall.sh`; add its admin host names to the first access rule in
`config/configuration.yml.template`, render, recreate Authelia.

**If percolator is down,** the other nodes' protected pages answer `500` (fail
closed). Their own break-glass is an SSH tunnel to the app's port.

- **A new app on another node** gets a client block here plus
  `oidc_client`-style secret generation; its plaintext secret then has to be copied to
  that node.
