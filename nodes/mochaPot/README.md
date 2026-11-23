# mochaPot

> **Carried over from the pre-move fleet (2026-11-16).** This page was written for
> the old layout and hardware. Paths and addresses were updated mechanically; the
> bring-up notes are still the best record of how this node's apps fit together,
> but check each step against [`docs/migration-plan.md`](../../docs/migration-plan.md)
> and [`docs/hardware.md`](../../docs/hardware.md) before relying on it.

**Music, the wall screen and the second resolver**: `192.168.1.13`, HP Pavilion
x360 (i5-7200U, 8 GB, 128 GB M.2 SATA, USB Ethernet), Debian 13 with a kiosk
session on its own touchscreen.

Home Assistant was here until 2026-11-22; it is on cellar now, on built-in
Ethernet ([docs/hardware.md](../../docs/hardware.md), "When a node goes down").
The wall screen shows it from there, straight to its port. The laptop battery
still earns its place: it keeps the second resolver up through a power cut.

| App | URL | What it's for |
|---|---|---|
| Music Assistant | `music.${DOMAIN}` (Authelia), or `:8095` | Whole-house audio |
| [Pi-hole](../../stacks/network/pihole-secondary/README.md) | `pihole-mochapot.${DOMAIN}` (admins), or `:8081` | Secondary DNS. **Never DHCP** |
| Traefik | — | HTTPS for the two above |
| [kiosk](../../stacks/home/kiosk/README.md) | the wall screen | cage + Chromium on tty1, host-native; shows Home Assistant on cellar |
| Komodo Periphery | — | Lets Komodo on cellar manage this node's containers |
| Scrutiny collector | — | SMART data for the hub on cellar |

Music Assistant and Pi-hole are host-networked (discovery and DNS need it), so
Traefik reaches them by URL and they see its requests coming from `proxy`
(`PROXY_SUBNET`). Their own ports stay open to the LAN: that's the way in when
Authelia or Traefik is down. Pi-hole has its own login there; Music Assistant
has none.

## Setup

As `barista` in `/opt/purrbrews/nodes/mochaPot`, once the node is set up (`docs/migration-plan.md`, phase 1):

```bash
./setup-secrets.sh      # asks for DOMAIN, TRAEFIK_ACME_EMAIL, the disk and the Cloudflare
                        # token; generates the rest; renders Traefik and the kiosk profile
sudo ./firewall.sh
```

Then, in order (`node.conf`):

| # | Command | Check |
|---|---|---|
| 1 | `./compose.sh pihole up -d` | `dig @192.168.1.13 gatus.${DOMAIN} +short` gives `192.168.1.10` |
| 2 | `./compose.sh musicassistant up -d` | players on the LAN show up |
| 3 | `./compose.sh traefik up -d` | certificates issued; both hostnames load |
| 4 | `./compose.sh komodo-periphery up -d`, `./compose.sh scrutiny-collector up -d` | mochaPot in Komodo and Scrutiny on cellar (copy `komodo-periphery/keys/core.pub` from cellar first) |
| — | `sudo ./kiosk/setup-kiosk.sh` | Home Assistant's dashboard (on cellar) on the screen after a reboot |

Pi-hole goes before Traefik because both want host ports; Pi-hole's UI moved to 8081
so Traefik can have 80.

## Things worth knowing

- **Never enable DHCP here.** sieve is the only DHCP server. The compose file pins
  it off, so don't fight it in the UI.
- **Host-networked containers keep the DNS they were created with.** Docker copies
  `resolv.conf` once, at create time. After a DNS change on this node,
  `./compose.sh <app> up -d --force-recreate`; a restart isn't enough.
- **Two Pi-holes, one set of records.** After a route is added anywhere, run
  `./render-configs.sh` and recreate Pi-hole here *and* on sieve.
- **Client DNS failover is weak.** Most clients wait out the primary before trying
  this one, so a sieve outage feels like slow browsing, not a clean switch. Real HA
  would be keepalived and a floating IP; not attempted.

## Data

| Path | Contents | Back up |
|---|---|---|
| `/srv/data/musicassistant` | library, players | optional |
| `/srv/data/pihole` | settings, query log | no; it's all in compose and generated |

## Known gaps

- **The kiosk's crash recovery is untested**: nothing restarts cage if Chromium
  exits, short of a reboot ([kiosk/README.md](../../stacks/home/kiosk/README.md)).
- **Blocklists aren't synced** between the two Pi-holes.
