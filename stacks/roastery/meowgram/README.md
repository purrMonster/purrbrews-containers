# meowGram (on roastery, for now)

The household's cat-lounge chat: a Flutter app (web, Android, desktop) and a Go
backend with Postgres, from its own repo, `purrMonster/meowGram`. It runs on
roastery in Docker Desktop from that repo's `deploy/docker-compose.yml`; nothing
of it is built from this repo. What lives here is the way in:

| | |
|---|---|
| URL | `https://meow.${DOMAIN}` |
| Route | roastery's native Traefik, [`traefik/config/dynamic/meow.yml.template`](../traefik/config/dynamic/meow.yml.template) → `http://127.0.0.1:8080` |
| Sign-in | Authelia OIDC on percolator, public client `meowgram` (PKCE), `household` policy |
| DNS | from the route, like every other (`dns-records.py`); the tunnel on sieve for outside |
| Data | Docker volume `meowgram-postgres-data` on roastery. **Not backed up yet** |

## Sign-in

No ForwardAuth: the phone and desktop apps can't follow that redirect. The app runs
the OIDC login itself, and the backend checks each request's access token against
Authelia's `/jwks.json`. So Authelia's `meowgram` client differs from the others:

- **public, no secret** (`token_endpoint_auth_method: none`, PKCE required);
- **JWT access tokens** (`RS256`), with `preferred_username`, `name` and `email`
  in them (the `meowgram` claims policy) and `aud` = `https://meow.${DOMAIN}`;
- **CORS** on Authelia's authorization, token, revocation and userinfo endpoints,
  for origins in a client's redirect URIs, since the web app calls them from the
  browser.

Redirect URIs: `https://meow.${DOMAIN}` (web, the home-screen PWA) and
`http://127.0.0.1:8088/callback` (desktop).

## Running it

From the meowGram checkout on roastery:

```powershell
docker compose --env-file .env --env-file deploy/.env -f deploy/docker-compose.yml up -d
```

- **`.env`** (repo root, gitignored): the app's values, also read by the Flutter
  client: `APP_DOMAIN=meow.<domain>`, `AUTHELIA_DOMAIN=authelia.<domain>`, …
- **`deploy/.env`** (gitignored, written 2026-10-04): the server's side and its
  secret: the Postgres password, `HOST_POSTGRES_PORT=127.0.0.1:5432` and
  `HOST_HTTP_PORT=127.0.0.1:8080` (**loopback only**: Traefik is the only way in),
  `AUTHELIA_ISSUER`, `AUTHELIA_JWKS_URL`, `CORS_ORIGINS=https://meow.<domain>`.

Leave out `deploy/.env` and the compose's defaults come back: both ports on every
interface, and the dev password that's in the meowGram repo.

The app's own builds need `AUTHELIA_ISSUER_URL=https://authelia.<domain>` and
`AUTHELIA_CLIENT_ID=meowgram` (its build script has `auth.`, `meowgram-client` and
a domain that isn't the fleet's).

## Bring up the route

1. percolator: `./render-configs.sh`, `./compose.sh authelia up -d --force-recreate`.
2. roastery: `.\render-configs.ps1`. Traefik watches `config/dynamic/` and picks
   up `meow.yml` without a restart, then gets its certificate.
3. sieve and mochaPot: refresh DNS so `meow.${DOMAIN}` points at roastery; sieve:
   render `cloudflared` and restart it, and add the tunnel's DNS route (2026-09-28
   tunnel entry).

## Is it working?

1. `curl.exe -s https://meow.${DOMAIN}/healthz` returns `"status":"ok"`.
2. `https://meow.${DOMAIN}/api/messages/sync?after=2026-01-01T00:00:00Z` without a
   token: `401`.
3. From another machine, `roastery:5432` and `roastery:8080` don't connect.
4. Signing in from the app goes to Authelia and comes back; messages show your
   username, not a long ID.

## Open

- **Backups:** the chat database is on roastery, outside every node's `backup`.
  Moving it to percolator (Postgres dumped nightly like the others) fixes that.
- **Nothing serves the web build yet**: the backend has no static files, so
  `https://meow.${DOMAIN}/` answers 404 until there's a web container or the
  backend serves `client/build/web`.
- **In the meowGram repo:** check `aud` instead of `SkipClientIDCheck` (it takes
  any JWT Authelia signs, other apps' ID tokens included); the token in
  `/ws?token=` (Cloudflare sees full URLs on the tunnel); an app link or scheme for
  Android/iOS; the build values above.
- **roastery is a workstation:** the chat is down whenever it is.
