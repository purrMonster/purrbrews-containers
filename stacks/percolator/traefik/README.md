# Traefik

Reverse proxy and TLS for every app on percolator. The only container that
publishes ports.

| | |
|---|---|
| Image | `traefik:v3.7.13` |
| URL | `https://traefik.${DOMAIN}` — dashboard, `purrbrews_admins` only (Authelia) |
| Ports | 80 → redirect, 443 |
| Data | `/srv/data/traefik/{letsencrypt,logs,plugins-local}` |
| Secrets | `CF_DNS_API_TOKEN` (you provide), `CROWDSEC_BOUNCER_KEY` (generated) |

## Files

| File | Role |
|---|---|
| `config/traefik.yml.template` | Entry points, wildcard certificate, Docker + file providers, plugin, access log |
| `config/dynamic.yml.template` | Shared middlewares (`authelia`, `crowdsec`, `security-headers`) and the dashboard route |
| `prepare.sh` | Run by `compose.sh` before `up`: puts the CrowdSec bouncer plugin, pinned to a verified commit, in `plugins-local` |
| `data-dirs` | Directories `compose.sh` creates before `up` |

App routes are not here: each app declares its own with labels in its
`docker-compose.yml`, so a route comes and goes with its app.

## How it behaves

- **Every HTTPS request** passes the `crowdsec` and `security-headers` middlewares,
  set once on the `websecure` entry point.
- **One wildcard certificate** for `${DOMAIN}` and `*.${DOMAIN}`, from Let's Encrypt
  via Cloudflare DNS-01. Renewal is automatic.
- **Real client addresses from the tunnel:** `X-Forwarded-For` is trusted only from
  `SIEVE_LAN_IP` (from `stacks/fleet.env`), where cloudflared runs.
- **No upload time limit** (`readTimeout: 0s`); Traefik v3's 60 s default breaks
  large Immich and Nextcloud uploads.
- **The CrowdSec plugin is a local plugin**, loaded from disk. A catalog plugin is
  downloaded on every start, and when that fails every route using it stops
  working — here that would be all of them.
- **Apps opt in** with `traefik.enable=true`; the Docker provider ignores everything else.
- **`authelia.${DOMAIN}` is a network alias of this container on `proxy`**, so apps
  reach Authelia through Traefik without LAN DNS.

## Bring up

```bash
sudo ./firewall.sh
./compose.sh traefik up -d
sudo docker logs -f traefik
```

## Is it working?

- [ ] Logs show `Plugins loaded` and no `Unable to obtain ACME certificate`.
- [ ] From a LAN browser, `https://anything.${DOMAIN}` shows a **valid** certificate
      for `*.${DOMAIN}` (a 404 page is expected before apps exist).
- [ ] `http://` redirects to `https://`.
- [ ] After Authelia is up: `https://traefik.${DOMAIN}` asks you to sign in, and
      opens for `barista`.

## Gotchas

- **The first certificate takes a minute or two** (DNS propagation for the
  challenge). Clients see Traefik's default self-signed certificate until then.
- **`invalid middleware "crowdsec@file"`** in the logs means the plugin didn't load:
  check `prepare.sh` output and `/srv/data/traefik/plugins-local`. Every route is
  down while this is the case.
- **Changing a template:** `./render-configs.sh`, then `./compose.sh traefik up -d`.
  The file provider watches `dynamic.yml`, but `traefik.yml` changes need a restart.
- **Upgrading the plugin:** edit `PLUGIN_TAG` and `PLUGIN_COMMIT` in `prepare.sh`
  together; it refuses a tag that doesn't resolve to the pinned commit.
- **The access log is not rotated yet.** Watch the size of `/srv/data/traefik/logs`.
