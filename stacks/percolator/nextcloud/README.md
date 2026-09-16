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

## Gotchas

- **`--mapping-uid=preferred_username --unique-uid=0`** gives readable user IDs
  (`barista`, not a hash). Set it before the first OIDC login; changing it later
  creates new, empty accounts.
- **Admin and DB passwords are first-start only.** Changing them in the secrets file
  later does nothing.
- **Upgrades go one major at a time** (34 → 35 → 36). Bump the tag, `pull`, `up -d`,
  wait for the upgrade in the logs before the next.
- **Postgres stays on 17** until Nextcloud lists 18 as supported. A Postgres major
  upgrade needs a dump and restore, never just a tag change.
