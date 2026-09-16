# Gatus

Health checks for the fleet, with alerts sent to phones. Image
`twinproduction/gatus:v5.36.0`. Dashboard at `gatus.${DOMAIN}`, through sieve's
Traefik and Authelia.

## Three layers of alerting

A monitor can't report its own death, so each layer covers the one before it:

| Layer | Catches | Delivered via |
|---|---|---|
| **Gatus checks** | a service or node failing | self-hosted ntfy → `purrbrews-alerts` |
| **Critical checks** (ntfy, tunnel) | the self-hosted delivery path failing | public ntfy.sh → `NTFY_CRITICAL_TOPIC` |
| **Heartbeat** | sieve, Gatus or the internet link failing | healthchecks.io, when pings stop |

Alerts fire after 3 failed checks in a row, and resolve after 2 good ones, with a
"resolved" message.

## Heartbeat

1. Create a free account at healthchecks.io → **Add Check**: name `sieve`, period
   **5 minutes**, grace **10 minutes**.
2. Copy the ping URL (`https://hc-ping.com/<uuid>`).
3. On sieve, run `./generate-secrets.sh` and paste it. It's stored in
   `gatus/secrets.env.local`.
4. Under Integrations, add email and/or the ntfy integration pointing at your ntfy.sh
   critical topic.

The *healthchecks.io heartbeat* endpoint in `config/config.yaml` fetches that URL
every 5 minutes. Its failures matter only in that healthchecks.io stops getting pings,
so it raises no alert of its own.

## What's checked

`config/config.yaml`, grouped on the dashboard:

- **network:**
  - Pi-hole recursion through Unbound, and the `*.${DOMAIN}` override;
  - the Pi-hole and NetAlertX web UIs;
  - Traefik's ping, and a real request to `https://gatus.${DOMAIN}` resolved through
    Pi-hole. That request checks the certificate has more than 10 days left and that
    SSO answers with a redirect or `401`: a `500` means Authelia is unreachable;
  - the tunnel's `/ready`;
  - ntfy, internally and through the tunnel;
  - the gateway and the internet (ICMP).
- **fleet:** ICMP for percolator, cellar, mochaPot and grinder. These are
  `enabled: false` until each node exists. Flip them on as nodes are provisioned, and
  add app checks as their stacks land.

The file is tracked. Gatus substitutes `${VARS}` from its environment itself, so no
rendered copy with secrets is ever written. After editing:
`./compose.sh gatus up -d --force-recreate`.

Two rules for new checks:

- **HTTP checks need `[CONNECTED] == true` alongside `[STATUS] < 400`.** A refused
  connection reports status 0, which is "less than 400", so the status condition
  alone passes on a dead service.
- **Pick the alert type by delivery path.** Use `ntfy` for most things. Use `custom`
  (ntfy.sh) only when the failure itself would stop ntfy on sieve reaching a phone.

## Test the alert path

A deliberate break, rather than trusting the config:

```bash
./compose.sh ntfy stop     # after ~3 min: critical alert on ntfy.sh
./compose.sh ntfy start    # after ~2 min: "back up" on ntfy.sh
```

For the routine path, stop NetAlertX the same way. The alert arrives on
`purrbrews-alerts`.

Tested before first deploy: Gatus alerts reached `purrbrews-alerts` with its token.
The ntfy.sh path could not be exercised from the test sandbox; the test above is the
real proof.

## Notes

- **No published port.** Gatus has no login; the dashboard is only reachable
  through Traefik + Authelia.
- **Alerts go straight to the ntfy container**, not through Traefik, so a broken
  proxy can still report itself.
- **Checks against host-network apps** (Pi-hole, NetAlertX) come from `sieve_edge`,
  which is why `firewall.sh` allows that subnet to ports 53, 8080 and 20211.
- **ICMP** uses unprivileged pings (Gatus ≥ 5.31), so no extra capability is needed.
- **Data:** `/srv/data/gatus/gatus.db` (SQLite, uptime history).
