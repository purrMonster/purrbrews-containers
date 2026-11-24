# Immich

Photo and video library with phone backup, sharing, face recognition and search.

| | |
|---|---|
| Images | `ghcr.io/immich-app/immich-server:v3.2.1`, `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, `valkey/valkey:9.1.2-alpine` |
| URL | `https://immich.${DOMAIN}` |
| Data | `/srv/data/immich/library` (originals, thumbnails, encoded video), `/srv/data/immich/postgres` |
| Secrets | `IMMICH_DB_PASSWORD`, `IMMICH_OIDC_CLIENT_SECRET` |
| Node | grinder (moved from percolator, 2026-11-23) |
| Depends on | `../../ai/immich-ml` on the same node (optional); percolator's Authelia (OIDC) and mail relay |

## Bring up

On grinder, after `immich-ml`. Copy the mail relay's public CA from percolator
first (it's public; the relay must have been `up` once there):

```bash
sudo install -d /srv/data/mail-relay/tls-public
scp barista@192.168.1.11:/srv/data/mail-relay/tls-public/ca.crt /tmp/ca.crt
sudo install -m 0644 /tmp/ca.crt /srv/data/mail-relay/tls-public/ca.crt
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
   `http://immich-machine-learning:3003`. Run *Jobs → Smart Search / Face Detection*.
4. On phones: server URL `https://immich.${DOMAIN}`, sign in with Authelia, enable backup.
5. *Administration → Settings → Notification Settings → Email* (mail goes through
   `../mail-relay`; Immich has no environment variables for it):
   - Enabled; Host `192.168.1.11` (percolator; the relay's certificate carries that
     address), Port `587`; Username and Password empty
   - *Ignore certificate errors* off: `NODE_EXTRA_CA_CERTS` gives Immich the relay's CA
   - From `Immich <purrBrews@${DOMAIN}>`
   - *Send test email*

## Is it working?

- [ ] `https://immich.${DOMAIN}/api/server/ping` returns `{"res":"pong"}`.
- [ ] *Login with Authelia* works in the browser **and** in the phone app
      (the app uses the `app.immich:///oauth-callback` redirect).
- [ ] A phone backup of a long video finishes (no cut-off at 60 s).
- [ ] *Administration → Jobs* shows Smart Search progressing, and
      searching for "dog" finds dogs.
- [ ] The Email settings' test mail arrives from `Immich <purrBrews@${DOMAIN}>`.

## Gotchas

- **Server and ML versions must match.** Bump `immich-server` here and
  `immich-machine-learning` in `../../ai/immich-ml` together.
- **Sign-in needs LAN DNS on grinder.** Unlike on percolator, there is no
  `authelia.${DOMAIN}` alias on grinder's `proxy` network: Immich reaches
  Authelia through Pi-hole's record for percolator. If *Login with Authelia*
  fails with a discovery error, check `dig authelia.${DOMAIN}` on grinder first.
- **Postgres image is Immich's own.** Never swap it for plain `postgres` or
  `pgvector`; migrations fail. Upgrade it only when Immich's release notes say so.
- **The database must be on local disk**, never NFS/SMB.
- **Machine learning on a CPU is slow.** The first pass over a library takes days;
  nothing else waits on it.
- **Read release notes before every bump**; Immich occasionally needs a manual step.
- **Library growth:** grinder has one 1 TB NVMe for the system and `/srv/data`.
  Watch `du -sh /srv/data/immich/library`.
