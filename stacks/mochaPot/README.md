# mochaPot

**Home automation, music and the wall screen**: `192.168.0.13`, HP Pavilion x360
(i5-7200U, 8 GB, 128 GB M.2 SATA), Debian 13 with a kiosk session on its own
touchscreen.

Home Assistant lives here rather than on percolator for blast radius: it shares a
failure domain with neither the app tier nor the network tier, the wall dashboard
still renders when percolator is down, and the laptop battery rides out a power cut.

| App | URL | What it's for |
|---|---|---|
| [Home Assistant](homeassistant/README.md) | `homeassistant.${DOMAIN}`, or `:8123` | Home automation; signs in with Authelia itself (OIDC) |
| Music Assistant | `music.${DOMAIN}` (Authelia), or `:8095` | Whole-house audio |
| [Pi-hole](pihole/README.md) | `pihole-mochapot.${DOMAIN}` (admins), or `:8081` | Secondary DNS. **Never DHCP** |
| Traefik | — | HTTPS for the three above |
| [kiosk](kiosk/README.md) | the wall screen | cage + Chromium on tty1, host-native |
| Komodo Periphery | — | Lets Komodo on cellar manage this node's containers |
| Scrutiny collector | — | SMART data for the hub on cellar |

Home Assistant, Music Assistant and Pi-hole are all host-networked (discovery and
DNS need it), so Traefik reaches them by URL and they see its requests coming from
`mochapot_net` (`PROXY_SUBNET`). Their own ports stay open to the LAN: that's the
way in when Authelia or Traefik is down. Home Assistant and Pi-hole have their own
logins there; Music Assistant has none.

## Setup

As `barista` in `/opt/purrbrews/stacks/mochaPot`, after `init/purrbrews-init.sh mochaPot`:

```bash
./setup-secrets.sh      # asks for DOMAIN, TRAEFIK_ACME_EMAIL, the disk and the Cloudflare
                        # token; generates the rest; renders Traefik and the kiosk profile
sudo ./firewall.sh
```

Then, in order (`node.conf`):

| # | Command | Check |
|---|---|---|
| 1 | `./compose.sh pihole up -d` | `dig @192.168.0.13 gatus.${DOMAIN} +short` gives `192.168.0.10` |
| 2 | `./compose.sh homeassistant up -d` | onboarding at `http://192.168.0.13:8123`; then the [configuration.yaml steps](homeassistant/README.md#configurationyaml) |
| 3 | `./compose.sh musicassistant up -d` | players on the LAN show up |
| 4 | `./compose.sh traefik up -d` | certificates issued; the three hostnames load (Home Assistant only once it trusts `PROXY_SUBNET`) |
| 5 | `./compose.sh komodo-periphery up -d`, `./compose.sh scrutiny-collector up -d` | mochaPot in Komodo and Scrutiny on cellar (copy `komodo-periphery/keys/core.pub` from cellar first) |
| — | `sudo ./kiosk/setup-kiosk.sh` | the dashboard on the screen after a reboot |

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
| `/srv/data/homeassistant` | config, automations, `secrets.yaml` | **yes** |
| `/srv/data/postgres-homeassistant` | recorder history | as a dump, if at all |
| `/srv/data/musicassistant` | library, players | optional |
| `/srv/data/pihole` | settings, query log | no; it's all in compose and generated |

## Known gaps

- **The kiosk's crash recovery is untested**: nothing restarts cage if Chromium
  exits, short of a reboot ([kiosk/README.md](kiosk/README.md)).
- **Home Assistant tracks `:stable`**, as upstream recommends. An update is a
  `pull` away, for better and worse.
- **Blocklists aren't synced** between the two Pi-holes.
