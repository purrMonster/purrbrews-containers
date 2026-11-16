# Pi-hole (secondary)

mochaPot's Pi-hole: **DNS only, never DHCP.** sieve is the one DHCP server, and the
compose file pins `dhcp.active` off so no saved UI setting can change that.

- Admin UI: `https://pihole-mochapot.${DOMAIN}` (Authelia), or
  `http://192.168.0.13:8081/admin` with its own password (`PIHOLE_WEBPASSWORD` in
  `secrets.env.local`). Its own password stays on because the direct port is the
  way in when Authelia is down.
- Upstream: Cloudflare, not sieve's Unbound, so it keeps answering when sieve is down.
- Records: the same split DNS as sieve, generated from every Traefik route in the
  repo (`../../_lib/dns-records.py`).

## Refreshing local DNS

After a route is added anywhere in the fleet:

```sh
./render-configs.sh            # regenerates the records (RESOLVER=secondary in node.conf)
./compose.sh pihole up -d      # recreate; a restart doesn't re-read the environment
```

Do the same on sieve. Keep `DOMAIN` and `PIHOLE_DNS_EXTRA_HOSTS` identical on both;
roastery isn't in `NODE_IPS`, so `192.168.0.20 roastery` (or whatever its fixed IP
is) has to be in `PIHOLE_DNS_EXTRA_HOSTS` on both for `ollama.${DOMAIN}` to resolve.
[The network audit](../../../docs/network-audit.md) has the rollout order and checks.

Blocklists are not synced between the two Pi-holes. If that ever matters, it needs
its own decision.
