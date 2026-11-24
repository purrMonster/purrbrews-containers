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
| [Karakeep](../../stacks/apps/karakeep/) | `karakeep.${DOMAIN}` (SSO), or `:3030` | Bookmarks and read-it-later. **Optional, not up yet** (2026-11-24) |
| [FitTrackee](../../stacks/apps/fittrackee/) | `fittrackee.${DOMAIN}` (SSO), or `:5001` | Rides, from the bike computer's GPX. **Optional, not up yet** |
| [Traccar](../../stacks/apps/traccar/) | `traccar.${DOMAIN}` (SSO), or `:8082`; the phone posts to `:5055` | Live position of the bike. **Optional, not up yet** |
| Traefik | — | HTTPS for all of the above |
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
| later | `./compose.sh karakeep up -d`, then `fittrackee`, `traccar`, when the owner asks | first visits below |
| 4 | `./compose.sh komodo-periphery up -d`, `./compose.sh scrutiny-collector up -d` | mochaPot in Komodo and Scrutiny on cellar (copy `komodo-periphery/keys/core.pub` from cellar first) |
| — | `sudo ../../stacks/home/kiosk/setup-kiosk.sh` | Home Assistant's dashboard (on cellar) on the screen after a reboot |

Pi-hole goes before Traefik because both want host ports; Pi-hole's UI moved to 8081
so Traefik can have 80.

## The self-tracking apps

Karakeep, FitTrackee and Traccar moved here from percolator on 2026-11-24
(owner), for percolator's memory and its 256 GB disk; they had come to
percolator from grinder the day before. They are optional (`fleet.json`) and
set aside for now: `--all` skips them until they're asked for. They sit behind
Authelia through this node's Traefik (`authelia-forwardauth@file`), each with
its own login behind that, and keep their own ports open to the LAN.

| App | First visit |
|---|---|
| Karakeep | Set `DISABLE_SIGNUPS: "false"` for the first account, then straight back to `"true"` and `up -d` again. Its `NEXTAUTH_URL` is the direct-port URL while the route is `karakeep.${DOMAIN}`: check the phone's share sheet signs in through the hostname. Image `release` is unpinned |
| FitTrackee | Create the first account (check whether it becomes admin on this version). |
| Traccar | **Log in as admin/admin and change it at once**; the image won't take it from the environment. The phone's server is `http://192.168.1.13:5055`. Traccar is on H2, not Postgres; fine for GPS pings |

| Port | Bound to | Owner |
|---|---|---|
| 3030, 5001, 8082 | published (UFW route: LAN, on the container ports 3000, 5000, 8082) | Karakeep, FitTrackee, Traccar |
| 5055 | published (UFW route: LAN) | Traccar's OsmAnd ingest, what the phone posts to; not HTTP |

| Path | Contents | Back up |
|---|---|---|
| `karakeep*`, `fittrackee`, `postgres-fittrackee`, `traccar` | bookmarks, rides, positions (Traccar on H2) | **yes** (Postgres as a dump) |

They are the apps that grow (Karakeep's archived pages, Traccar's positions),
on the fleet's smallest disk, the SanDisk with a history of timeouts. Watch
`df -h /` and Scrutiny; the spare 128 GB M.2 SATA is the way out.

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
