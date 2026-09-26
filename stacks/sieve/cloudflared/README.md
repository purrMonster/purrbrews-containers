# cloudflared

The Cloudflare Tunnel: an outbound connection from sieve to Cloudflare's edge. The
house is behind CGNAT, so this is the only way in from the internet, and no port is
opened on the router or on sieve. Image `cloudflare/cloudflared:2026.9.1`.

## Create the tunnel

The tunnel is **remotely managed**. Its routes live in the Cloudflare dashboard, and
sieve holds only a token.

1. Cloudflare dashboard → **Zero Trust → Networks → Tunnels → Create a tunnel** →
   *Cloudflared*, name it `sieve`.
2. On the install page, copy the token: the long string after `--token`. You don't
   need to install anything, since the container is the connector.
3. On sieve, run `./setup-secrets.sh` and paste the token when asked. It's stored
   in `cloudflared/secrets.env.local`.
4. `./compose.sh cloudflared up -d`. The tunnel turns **Healthy** in the dashboard
   within a minute.

## Public hostnames

Add these under the tunnel's **Published application routes** (called *Public
Hostnames* in older dashboards). cloudflared resolves container names on
`sieve_edge`.

| Hostname | Service | Notes |
|---|---|---|
| `ntfy.${DOMAIN}` | `http://ntfy:8080` | Straight to the container, so it doesn't depend on Traefik |

Apps on other nodes go to **that node's** Traefik:

| Hostname | Service | Additional settings → TLS |
|---|---|---|
| `<app>.${DOMAIN}` | `https://<node IP>:443` | **Origin Server Name** = `<app>.${DOMAIN}` |

- Use `https://…:443`, not `http://…:80`. Traefik redirects HTTP to HTTPS, and
  cloudflared passes that redirect back to the browser, which loops.
- Set **Origin Server Name**. Otherwise cloudflared sends the IP as the SNI, Traefik
  presents its default self-signed certificate, and the route fails with a 502.

These settings exist only in the Cloudflare dashboard. Record every route you add in
this table, so a rebuilt tunnel can be recreated from it.

**Never route** Pi-hole (8080) or NetAlertX (20211) straight to their ports, and don't
publish sieve's admin UIs at all. They have no login of their own; on the LAN they are
behind Authelia.

## Checks

```bash
./compose.sh cloudflared logs --tail 20      # "Registered tunnel connection" ×4
sudo docker run --rm --network sieve_edge curlimages/curl -s http://cloudflared:2000/ready
```

Gatus checks `/ready` every minute and alerts through ntfy.sh if the tunnel drops.
While the tunnel is down, the self-hosted ntfy can't reach phones that are away from
home.

## Notes

- `--no-autoupdate`: the image tag is the version, and upgrades are a tag bump.
- `--metrics 0.0.0.0:2000` is reachable only on `sieve_edge`; the port is not published.
- Rotating the token: dashboard → tunnel → *Refresh token*. Then delete `TUNNEL_TOKEN`
  from `secrets.env.local`, re-run `./setup-secrets.sh` and recreate the container.
