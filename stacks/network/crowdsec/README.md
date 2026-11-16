# CrowdSec

Watches Traefik's access log for attack patterns (scanners, brute force, known
CVE probes) and tells the Traefik bouncer plugin which addresses to refuse.

| | |
|---|---|
| Image | `crowdsecurity/crowdsec:v1.7.8` |
| URL | none |
| Ports | none — the plugin reaches `crowdsec:8080` on `proxy` |
| Data | `/srv/data/crowdsec/{data,config}` |
| Secrets | `CROWDSEC_BOUNCER_KEY` (generated; the same value is in `traefik/secrets.env.local`) |

## How it behaves

- **Collections:** `crowdsecurity/traefik` (HTTP scenarios) and `crowdsecurity/linux`,
  which brings the whitelist that never bans private addresses.
- **Enforcement is in Traefik, not the host firewall.** Everything that reaches
  percolator's apps comes through Traefik, and tunnel visitors arrive from sieve's
  address, so a host firewall bouncer could never tell them apart. The plugin sees
  their real address through `X-Forwarded-For`.
- **The bouncer registers itself:** `BOUNCER_KEY_traefik` creates it at startup with
  a key generated on this node. No `cscli bouncers add` step.
- **LAN addresses are never blocked** by the bouncer (`clientTrustedIPs`), whatever
  CrowdSec decides.
- **If CrowdSec is down, Traefik keeps serving** with the last decisions it had.

## Bring up

After Traefik:

```bash
./compose.sh crowdsec up -d
sudo docker logs -f crowdsec
```

## Is it working?

- [ ] `sudo docker exec crowdsec cscli bouncers list` shows `traefik`, valid, with a
      recent *Last API pull*.
- [ ] `sudo docker exec crowdsec cscli metrics` shows lines read from
      `/var/log/traefik/access.log` after browsing an app.
- [ ] Ban test with a documentation address (expires by itself):
      ```bash
      sudo docker exec crowdsec cscli decisions add --ip 198.51.100.7 --duration 2m --reason test
      sudo docker exec crowdsec cscli decisions list
      ```
      Within a minute the Traefik logs show the plugin's cache update. A real blocked
      request can only be tested from outside the LAN, through the tunnel.

## Everyday commands

```bash
sudo docker exec crowdsec cscli decisions list
sudo docker exec crowdsec cscli decisions delete --ip <address>
sudo docker exec crowdsec cscli alerts list
sudo docker exec crowdsec cscli hub update && sudo docker exec crowdsec cscli hub upgrade
```

## Gotchas

- **Needs internet at startup** to install collections from the hub; without it the
  container restarts until it can. Traefik is unaffected.
- **Check real addresses once the tunnel is live:** the `ClientHost` field in
  `/srv/data/traefik/logs/access.log` for a tunnel request must be the visitor's
  address, not `192.168.0.10`. If it's sieve's, nothing from the tunnel can be banned.
