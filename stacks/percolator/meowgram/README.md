# meowGram

The household's cat-lounge chat: a Flutter app (web, Android, iOS, Windows,
macOS) and a Go backend with Postgres, from its own repo, `purrMonster/meowGram`.
Moved from roastery on 2026-10-14 (runbook): the chat now stays up when roastery
sleeps or games, and its database is in percolator's nightly dumps.

| | |
|---|---|
| Images | `ghcr.io/purrmonster/meowgram-server` and `meowgram-web`, built by meowGram's release workflow from a version tag; `postgres:18.6`. meowGram's own compose builds from source, for its testing only |
| URL | `https://meow.${DOMAIN}` (web app; `/api`, `/ws`, `/healthz` go to the backend) |
| Sign-in | Authelia OIDC, public client `meowgram` (PKCE), `household` policy. No ForwardAuth |
| Data | `/srv/data/meowgram/postgres` (dumped nightly, `backup`), `/srv/data/meowgram/secrets` (push key, optional) |
| Secrets | `MEOWGRAM_DB_PASSWORD` (generated); the Firebase service account, if push is wanted |
| Published ports | none: Traefik only |

## Sign-in

No ForwardAuth: the phone and desktop apps can't follow that redirect. The app runs
the OIDC login itself, and the backend checks each request's access token against
Authelia's `/jwks.json`. So Authelia's `meowgram` client differs from the others:

- **public, no secret** (`token_endpoint_auth_method: none`, PKCE required);
- **JWT access tokens** (`RS256`), with `preferred_username`, `name` and `email`
  in them (the `meowgram` claims policy) and `aud` = `https://meow.${DOMAIN}`,
  which is the only audience the backend accepts (`AUTHELIA_AUDIENCE`);
- **CORS** on Authelia's authorization, token, revocation and userinfo endpoints,
  for origins in a client's redirect URIs, since the web app calls them from the
  browser.

Redirect URIs: `https://meow.${DOMAIN}` (web, the home-screen PWA),
`http://127.0.0.1:8088/callback` (desktop) and `meowgram://callback` (Android,
iOS: the app's own scheme, safe because of PKCE).

No default account: the first sign-in through Authelia creates the user from the
token's `sub`. Anyone in `${LLDAP_HOUSEHOLD_GROUP}` can sign in.

## Bring up

```bash
./setup-secrets.sh                 # makes MEOWGRAM_DB_PASSWORD
./compose.sh meowgram up -d
```

Then, once:

1. sieve **and** mochaPot: `./render-configs.sh`, `./compose.sh pihole up -d`, so
   `meow.${DOMAIN}` points at percolator instead of roastery.
2. sieve: `./render-configs.sh`, `./compose.sh cloudflared up -d --force-recreate`
   (the tunnel's `meow` route now goes to percolator), and in the Cloudflare
   dashboard move the published `meow.${DOMAIN}` route to percolator HTTPS with
   SNI `meow.${DOMAIN}` (the live tunnel is dashboard-managed).
3. sieve: `./compose.sh gatus up -d --force-recreate` for the new check.

### Push notifications (optional)

Copy the Firebase service account (meowGram's Firebase project) to
`/srv/data/meowgram/secrets/fcm-service-account.json` as the ops user, set
`MEOWGRAM_FCM_CREDENTIALS=/run/secrets/fcm-service-account.json` in `.env.local`,
then `./compose.sh meowgram up -d`. Without it the chat works; phones just
don't get notified while the app is closed.

## Is it working?

- [ ] `meowgram-postgres`, `meowgram-server` and `meowgram-web` are `healthy`.
- [ ] `curl -s https://meow.${DOMAIN}/healthz` returns `"status":"ok"`.
- [ ] `curl -s https://meow.${DOMAIN}/api/client-config` shows `issuer`
      `https://authelia.${DOMAIN}` and `client_id` `meowgram`.
- [ ] `https://meow.${DOMAIN}/api/messages/sync?after=2026-01-01T00:00:00Z`
      without a token: `401`.
- [ ] `https://meow.${DOMAIN}/` loads the web app; signing in goes to Authelia and
      back, and messages show your username, not a long ID.
- [ ] The Android app (published APK) signs in: Authelia opens in the browser and
      hands back to meowGram.
- [ ] A message sent from the web shows on a second device without a refresh (the
      WebSocket through Traefik).
- [ ] `ss -tlnp` on percolator shows nothing new; `5432` and `8080` aren't
      reachable from the LAN.
- [ ] `sudo ./backup.sh plan` lists the `meowgram` dump; after the next nightly,
      `DUMP_DIR/percolator/meowgram/` on cellar has it.

## Upgrades

A meowGram release (`vX.Y.Z` tag in its repo) pushes both images to GHCR;
Dependabot proposes the bump here a week later, as one PR per image. **Merge the
server and web PRs together**: the web app expects the backend of its release.
The server migrates the database at start, so take a dump first
(`sudo ./backup.sh nightly`).

## Gotchas

- **401 on every call right after a good sign-in**: likely the token's `aud` isn't
  `https://meow.${DOMAIN}`. Check Authelia's `meowgram` client still has
  `audience` and `requested_audience_mode: implicit`.
- **The web app and the backend must share one origin.** The published web image
  has no domain in it; it finds the backend on its own origin. Both routers are on
  `meow.${DOMAIN}`; don't split them onto two names.
- **Rate limits count Traefik, not the person.** The backend ignores forwarded
  headers on purpose (they can be forged), so the global bucket is shared by every
  client; the per-user buckets are what limit one person.

