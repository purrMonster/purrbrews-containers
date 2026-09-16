# Immich

Photo and video library with phone backup, sharing, face recognition and search.

| | |
|---|---|
| Images | `ghcr.io/immich-app/immich-server:v3.2.1`, `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, `valkey/valkey:9.1.2-alpine` |
| URL | `https://immich.${DOMAIN}` |
| Data | `/srv/data/immich/library` (originals, thumbnails, encoded video), `/srv/data/immich/postgres` |
| Secrets | `IMMICH_DB_PASSWORD`, `IMMICH_OIDC_CLIENT_SECRET` |
| Depends on | roastery's `immich-machine-learning` at `IMMICH_ML_URL` (optional) |

## Bring up

```bash
./compose.sh immich up -d
./compose.sh immich logs -f immich-server
```

## First run

1. Open `https://immich.${DOMAIN}` and create the admin account (the first account is
   the admin). Use your LLDAP email.
2. *Administration → Settings → Authentication Settings → OAuth*:
   - Issuer URL `https://authelia.${DOMAIN}`
   - Client ID `immich`, Client Secret = `IMMICH_OIDC_CLIENT_SECRET` from `immich/secrets.env.local`
   - Scope `openid email profile`, Token endpoint auth method `client_secret_basic`
   - Button text `Login with Authelia`
   - *Auto register*: on if household members should get accounts on first sign-in
3. *Administration → Settings → Machine Learning*: the URL should already be
   `IMMICH_ML_URL`. Run *Jobs → Smart Search / Face Detection* once roastery answers.
4. On phones: server URL `https://immich.${DOMAIN}`, sign in with Authelia, enable backup.

## Is it working?

- [ ] `https://immich.${DOMAIN}/api/server/ping` returns `{"res":"pong"}`.
- [ ] *Login with Authelia* works in the browser **and** in the phone app
      (the app uses the `app.immich:///oauth-callback` redirect).
- [ ] A phone backup of a long video finishes (no cut-off at 60 s).
- [ ] With roastery awake: *Administration → Jobs* shows Smart Search progressing, and
      searching for "dog" finds dogs.

## Gotchas

- **Server and ML versions must match.** Bump `immich-server` here and
  `immich-machine-learning` on roastery together.
- **Postgres image is Immich's own.** Never swap it for plain `postgres` or
  `pgvector`; migrations fail. Upgrade it only when Immich's release notes say so.
- **The database must be on local disk**, never NFS/SMB.
- **Roastery asleep = no new faces or smart-search indexing**, nothing else breaks.
  Jobs resume when it wakes.
- **Read release notes before every bump**; Immich occasionally needs a manual step.
- **Library growth:** `/srv/data` is 1 TB. Watch `du -sh /srv/data/immich/library`.
