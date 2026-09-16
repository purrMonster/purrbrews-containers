# Traefik

sieve's own reverse proxy. It gives sieve's web UIs real HTTPS certificates and puts
them behind single sign-on. Image `traefik:v3.7.13`.

Every node runs its own Traefik for its own apps. A broken proxy, a bad route or a
dead node then takes down only that node's pages, never the whole fleet's.

## Routes

`dynamic/sieve.yml`:

| Host | Backend | Auth |
|---|---|---|
| `pihole.${DOMAIN}` | Pi-hole, `host.docker.internal:8080` (`/` → `/admin/`) | Authelia |
| `gatus.${DOMAIN}` | `gatus:8080` | Authelia |
| `netalertx.${DOMAIN}` | NetAlertX, `host.docker.internal:20211` | Authelia |
| `traefik-sieve.${DOMAIN}` | Traefik's dashboard | Authelia |
| `ntfy.${DOMAIN}` | `ntfy:8080` | ntfy's own accounts |

- Pi-hole and NetAlertX use host networking, so Traefik reaches them through the
  host gateway. The firewall opens their ports to `sieve_edge` only.
- `ntfy.${DOMAIN}` is served here on the LAN, and by the Cloudflare tunnel outside.
  Phones at home therefore don't need the internet to get an alert.
- The dashboard name carries the node (`traefik-<node>`), because every node has one.

**Adding a route:** add a router and service to `dynamic/sieve.yml`; Traefik picks
up the change live. Then, so the name resolves on the LAN, run `./setup-secrets.sh`
followed by `./compose.sh pihole up -d`. The DNS records are generated from the
router rules in every node's Traefik files and compose labels (see
[Pi-hole's README](../pihole/README.md#app-host-names)).

The dynamic files are Go templates. `{{ env "DOMAIN" }}` and `{{ env "AUTHELIA_URL" }}`
come from the container's environment, so nothing is rendered to disk. Keep each
`rule: Host(`<name>.{{ env "DOMAIN" }}`)` on one line, exactly in that form, or no DNS
record is generated for it.

## Why a direct hop to Authelia

The `authelia` middleware calls `AUTHELIA_URL/api/authz/forward-auth`, which is
`http://192.168.0.11:9091`: Authelia's own published port on percolator. Two
alternatives look tidier and don't work:

- **Through percolator's Traefik** (`https://auth.${DOMAIN}/…`). ForwardAuth
  describes the original request in `X-Forwarded-Method/Proto/Host/Uri`. A second
  Traefik treats the call as an ordinary request and rewrites or drops those headers,
  so Authelia answers `400` (header `X-Forwarded-Method` is empty).
- **By container name.** Docker networks don't span hosts.

Also required, and already in place:

- **HTTPS on the protected routers.** Authelia refuses to issue a session for a
  target URL with an `http` scheme.
- **`trustForwardHeader: true`.**

Tested before first deploy, against a stub auth server:

- all four protected hosts send an unauthenticated request to login;
- a request with a valid session reaches the app;
- ntfy passes without auth;
- `:80` redirects to `:443`;
- Authelia receives `X-Forwarded-Method`, `Proto` (`https`), `Host` and `Uri`.

**Failure mode:** if percolator or Authelia is unreachable, the protected routes
answer `500`. They fail closed, and Gatus reports it. ntfy is unaffected.

## Certificates

Let's Encrypt, DNS-01 through Cloudflare, so nothing has to be reachable from the
internet. Each router gets a certificate for its own name.

- **Never request a certificate set another node also requests.** percolator holds
  the `${DOMAIN}` + `*.${DOMAIN}` wildcard; if sieve asked for the same set, the two
  would share Let's Encrypt's limit of five identical certificates a week, and a
  couple of rebuilds would exhaust it.
- **Trade-off:** per-name certificates put `pihole`, `gatus`, `netalertx`, `ntfy` and
  `traefik-sieve` under your domain in public certificate-transparency logs. The
  names reveal nothing exploitable, and none of them is reachable from outside.

Create the token in the Cloudflare dashboard: **My Profile → API Tokens → Create
Token → Edit zone DNS** template, limited to your zone. `./generate-secrets.sh` asks
for it. The same token can be used on every node.

Certificates are stored in `/srv/data/traefik/letsencrypt/acme.json` (root, 0700
directory). If it's lost, Traefik simply reissues on start.

Gatus checks `https://gatus.${DOMAIN}` every 15 minutes, resolved through Pi-hole.
It alerts when the certificate has less than 10 days left, or when the auth answer
isn't a redirect or a `401`.

## Checks

```bash
./compose.sh traefik logs --tail 30        # no "unable to obtain ACME certificate"
docker ps | grep traefik                   # (healthy)
curl -sI https://gatus.${DOMAIN} | head -1 # from a LAN client: 302 to Authelia's login
```

## Notes

- **No Docker socket.** Routing is file-only, so Traefik has no root-equivalent
  access to the host.
- **Hardening:** read-only root filesystem, all capabilities dropped except binding
  :80/:443, anonymous usage reporting off.
- **Header spoofing:** both entry points delete headers that alias managed ones
  (`aliasHeadersStrategy=delete`).
- **`maxResponseBodySize`** caps Authelia's replies at 64 KB.
