# NetAlertX

Knows what's on the LAN: a device inventory, presence, and alerts for new or
disappeared devices. Image `ghcr.io/netalertx/netalertx:26.9.0`. Dashboard at
`netalertx.${DOMAIN}`, through sieve's Traefik and Authelia.

## How it's set up

- **Host networking**, because ARP and nmap scans need layer 2 access to the LAN.
- **Hardened** per NetAlertX's own baseline compose file: read-only root filesystem,
  all capabilities dropped except the scan and entrypoint ones, and `/tmp` on a
  `noexec` tmpfs.
- **Settings forced on every start** through `APP_CONF_OVERRIDE`:

  | Setting | Value |
  |---|---|
  | `SCAN_SUBNETS` | `LAN_CIDR` on `LAN_INTERFACE` (detected by `setup-secrets.sh`) |
  | `SETPWD_enable_password` | `false` (Authelia in front of Traefik is the gate; see below) |
  | `BACKEND_API_URL` | `/server`, so the UI reaches the API through its own nginx and only port 20211 needs proxying |
  | `REPORT_DASHBOARD_URL` | `https://netalertx.${DOMAIN}` |

  Tested before first deploy: all four show as *overridden by env* in NetAlertX's
  settings, and the UI serves without a login.

Everything else (plugins, notification settings, device names) is managed in the UI
and stored in `/srv/data/netalertx`.

## No login, so the firewall matters

NetAlertX has had unauthenticated remote-code-execution CVEs (CVE-2024-46506,
CVE-2025-32440). Both were fixed long before this tag, but it's not an app to leave
open. Two things keep it closed, and both must hold:

- UFW opens port 20211 to `sieve_edge` only (Traefik and Gatus), not the LAN;
- the backend API port 20212 has no rule at all.

Never route it through the tunnel.

## First start

```bash
./compose.sh netalertx up -d
```

After the first scan cycle (about 5 minutes), open the dashboard and check that the
device count looks like the house: phones, TVs and the other nodes, not just the
gateway and sieve. A wrong interface doesn't produce an error; it produces an empty
list. If that happens, check `LAN_INTERFACE` in `.env.local` against
`ip -4 route show default`.

Worth doing in the UI:

- **Pi-hole integration** (the `PIHOLEAPI` plugin, URL `http://127.0.0.1:8080`, no
  password; both apps share the host network). Pulls hostnames and DHCP leases, so devices show names rather than MACs.
- **Notifications → ntfy** (`NTFY` publisher): host `https://ntfy.${DOMAIN}`, and a
  token for a dedicated ntfy user with write access to its topic, added as described
  in [`../ntfy/README.md`](../ntfy/README.md#adding-someone). The internal
  `http://ntfy:8080` isn't reachable from host networking.
- **Name the fleet nodes.** They appear with their cloned `02:…` MACs from
  `init/purrbrews-mac.sh list`.

## Notes

- **No `sysctls:`.** The baseline file sets ARP-flux sysctls, but Docker won't apply
  network-namespace sysctls in host network mode. They matter only with several NICs
  on one subnet. If you want them anyway, set them on the host:
  `echo -e 'net.ipv4.conf.all.arp_ignore=1\nnet.ipv4.conf.all.arp_announce=2' | sudo tee /etc/sysctl.d/90-netalertx.conf && sudo sysctl --system`.
- **Timezone** comes from the host's `/etc/localtime`, not `TZ`.
- **Memory** is capped at 1 GB; it idles well below that.
