# Nextcloud

Files, calendars and contacts, synced to phones and laptops.

| | |
|---|---|
| Images | `nextcloud:34.0.4-apache`, `postgres:17`, `valkey/valkey:9.1.2-alpine` |
| URL | `https://nextcloud.${DOMAIN}` |
| Data | `/srv/data/nextcloud/html` (app, config, user files), `/srv/data/nextcloud/postgres` |
| Secrets | `NEXTCLOUD_ADMIN_PASSWORD`, `NEXTCLOUD_DB_PASSWORD`, `NEXTCLOUD_OIDC_CLIENT_SECRET` |

Four containers: `nextcloud` (web), `nextcloud-cron` (background jobs every 5
minutes), `nextcloud-postgres`, `nextcloud-valkey` (file locking and cache). Only the
web container is on `proxy`.

## Bring up

```bash
./compose.sh nextcloud up -d
./compose.sh nextcloud logs -f nextcloud    # first start installs; wait for "resuming normal operations"
```

## First run

1. Sign in at `https://nextcloud.${DOMAIN}` as `admin` / `NEXTCLOUD_ADMIN_PASSWORD`.
2. *Administration settings → Basic settings → Background jobs*: choose **Cron**.
3. Install and configure sign-in with Authelia:
   ```bash
   S=$(grep ^NEXTCLOUD_OIDC_CLIENT_SECRET= nextcloud/secrets.env.local | cut -d= -f2)
   D=$(grep ^DOMAIN= .env.local | cut -d= -f2)
   occ() { sudo docker exec -u www-data nextcloud php occ "$@"; }
   occ app:install user_oidc
   occ config:system:set user_oidc default_token_endpoint_auth_method --value=client_secret_post
   occ config:system:set user_oidc enrich_login_id_token_with_userinfo --value=true --type=boolean
   occ user_oidc:provider Authelia --clientid=nextcloud --clientsecret="$S" \
     --discoveryuri="https://authelia.${D}/.well-known/openid-configuration" \
     --mapping-uid=preferred_username --unique-uid=0
   ```
4. Sign out and use *Log in with Authelia*. Keep `/login?direct=1` in mind: it always
   shows the password form, for the `admin` account.
5. *Administration settings → Overview* should show no errors.

## Is it working?

- [ ] Login page loads, no "untrusted domain" and no redirect loop.
- [ ] *Log in with Authelia* signs `barista` in as user `barista`.
- [ ] *Administration → Overview*: no security or setup warnings about reverse proxy,
      caching or background jobs (last job ran within minutes).
- [ ] A phone's CalDAV/CardDAV account set up with just `https://nextcloud.${DOMAIN}`
      finds calendars (the `.well-known` redirect works).
- [ ] Uploading a file larger than 1 GB through the browser completes.

## Clearing Administration → Overview warnings (2026-09-17)

Most of the *Security & setup warnings* Nextcloud shows after a fresh install are
one-time `occ` settings, not actual problems:

```bash
occ() { sudo docker exec -u www-data nextcloud php occ "$@"; }

# Run heavy background jobs at low-usage hours instead of during the day.
# Value is a UTC hour (0-23); 21 UTC = ~2:30 AM IST.
occ config:system:set maintenanceWindowStart --type=integer --value=21

# Picks up any new mimetypes added since this instance was installed.
# Can take a while on a large instance — fine to run any time, not just now.
occ maintenance:repair --include-expensive

# Lets phone numbers be entered without a country code in profile settings.
occ config:system:set default_phone_region --value=IN

# Only matters for multi-PHP-server setups; harmless to set anyway (0-1023, not -1).
occ config:system:set serverid --value=0
```

**HSTS** is *not* an `occ` setting here — see the `nextcloud-hsts` Traefik middleware
added to this file's labels (2026-09-17). Nextcloud's Apache only ever sees plain
HTTP from Traefik, so the header has to come from the proxy, not `.htaccess`
(which upgrades/`occ maintenance:update:htaccess` would just regenerate anyway).

The rest are decisions, not fixes — left alone deliberately until asked for:

- **AppAPI deploy daemon**: only needed to install Ex-Apps (which need Docker
  socket access for Nextcloud to manage). Not configured — bigger security
  surface than this instance currently needs.
- **Second factor not enforced**: Authelia is already the front door
  (`access_control` in its config) for `nextcloud.${DOMAIN}`; whether Nextcloud's
  *own* 2FA on top of that is worth the extra prompt is a household-UX call, not
  a security gap by itself.
- **Email test**: needs a real SMTP relay (a Gmail app password, or another
  provider) that isn't wired up anywhere in this repo yet — *Administration →
  Basic settings* once one exists.
- **1 warning in the logs**: check *Administration → Logging* (or
  `occ log:tail`) for what it actually says before treating it as generic noise.

## Gotchas

- **"Could not reach the OpenID Connect provider" after step 3.** Nextcloud's
  SSRF guard blocks outbound requests to private/local IP ranges by default.
  Traefik's `proxy` network alias for `authelia.${DOMAIN}` (see
  `../traefik/docker-compose.yml`) and the LAN's own DNS record both resolve
  it to a private address either way (Docker bridge or `192.168.0.11`), so
  Nextcloud refuses the discovery request even though it's perfectly
  reachable. Fix: `occ config:system:set allow_local_remote_servers --type=bool --value=true`
  (no restart needed). If it's still failing after that, check reachability
  directly rather than guessing further: `docker exec nextcloud getent hosts
  authelia.${DOMAIN}` and `docker exec nextcloud curl -vk
  https://authelia.${DOMAIN}/.well-known/openid-configuration`.
- **`--mapping-uid=preferred_username --unique-uid=0`** gives readable user IDs
  (`barista`, not a hash). Set it before the first OIDC login; changing it later
  creates new, empty accounts.
- **Admin and DB passwords are first-start only.** Changing them in the secrets file
  later does nothing.
- **Upgrades go one major at a time** (34 → 35 → 36). Bump the tag, `pull`, `up -d`,
  wait for the upgrade in the logs before the next.
- **Postgres stays on 17** until Nextcloud lists 18 as supported. A Postgres major
  upgrade needs a dump and restore, never just a tag change.
