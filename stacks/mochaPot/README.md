# mochaPot

Home automation and household screen — 192.168.0.13, HP Pavilion x360
(i5-7200U, 8 GB RAM, 128 GB M.2 SATA), running Debian 13 with a kiosk
session per `infrastructure.md` §2.

This stack directory was **rebuilt from scratch on 2026-09-16** for the
post-restructure fleet — it is not a migration of the pre-restructure
`purrBrews-infra` mochaPot build, even though a couple of files below were
adapted from it (and one, Home Assistant, moved here *from a different
node*, not from the old mochaPot at all). Treat everything here as a new
project: nothing is assumed to already be running, no `.env.local` or
`secrets.env.local` carries over, and every setup step below starts from a
bare Debian 13 (+ kiosk session) node that has already been through
`init/purrbrews-init.sh`.

**mochaPot runs four things**, per `infrastructure.md` §4, plus its own
Traefik added 2026-09-16 so homeassistant/musicassistant/pihole get real
HTTPS on pretty hostnames instead of bare LAN IP:port:

| App | What it does |
|---|---|
| [homeassistant](#homeassistant) | Home automation — **moved here from percolator** |
| [musicassistant](#musicassistant) | Whole-home audio / player discovery |
| [pihole](#pihole) | Secondary DNS resolver — **DNS only, never DHCP** |
| [kiosk](#kiosk) | The household wall dashboard, host-native |
| [traefik](#traefik) | Reverse proxy + real TLS, with a native-login backdoor |
| [komodo-periphery](#komodo-periphery--scrutiny-collector) | Agent for cellar's Komodo Core — added 2026-09-16 |
| [scrutiny-collector](#komodo-periphery--scrutiny-collector) | Pushes SMART data to cellar's Scrutiny hub — added 2026-09-16 |

Everything else the pre-restructure mochaPot ran — Jellyfin, Immich,
Vikunja, n8n, FreshRSS, Mealie, Actual Budget, Stirling PDF, Roundcube,
Traefik, its own Komodo Periphery — moved to other nodes or was cut
outright (Roundcube and Stirling PDF are in `infrastructure.md` §4's
"Deliberately not running" list). Nothing below tries to recreate them
here.

## Why mochaPot, specifically

`infrastructure.md` §4's placement rules, stated plainly for the one app
that actually moved nodes:

> Home Assistant lives on `mochaPot` for blast radius and locality: it
> shares a failure domain with neither the app tier nor the network tier,
> the wall dashboard renders locally if `percolator` is down, and the
> laptop battery rides out a power cut. Reversible in an evening if it
> proves wrong.

Music Assistant and the kiosk browser follow the same locality logic —
they're the household-facing pieces that should keep working even when
the rest of the fleet is having a bad night. Pi-hole here is explicitly
the *secondary* resolver, DNS only (`infrastructure.md` §5): "Never run
two DHCP servers on one LAN... mochaPot's Pi-hole serves DNS only." `sieve`
remains the fleet's only DHCP server.

## Traefik and the native-login backdoor

mochaPot now runs its own Traefik (added 2026-09-16), fronting all three
web-facing apps: `homeassistant.${DOMAIN}`, `music.${DOMAIN}`,
`pihole-mochapot.${DOMAIN}` (not `pihole.${DOMAIN}` — that hostname
belongs to sieve's primary instance once it's migrated into this repo).
Real TLS via Cloudflare DNS-01, same mechanism every other node's Traefik
in this fleet uses.

All three apps' host-networked ports (`8123`, `8095`, `8081`) stay published
directly alongside the Traefik route — that's the deliberate backdoor. The
pretty hostname goes through Traefik's `authelia-forwardauth` middleware,
which needs percolator's Authelia up and reachable. The direct
`http://${MOCHAPOT_LAN_IP}:<port>` path bypasses both entirely and lands
on the app's own native login: Home Assistant's local account, and
Pi-hole's own real web password (kept ON here, unlike sieve's primary
instance which disables its own password in favor of Authelia alone —
see `pihole/docker-compose.yml`'s own comment). Music Assistant has no
native login at all, same caveat cellar's Scrutiny carries.

## First-time setup on mochaPot

```sh
cd /opt/purrbrews/stacks/mochaPot
./setup-secrets.sh
```

Creates `.env.local` from `local.env.example`, prompts for every
`REPLACE_ME` (LAN IP, domain), runs `generate-secrets.sh`, then
`render-configs.sh` (this also renders `kiosk/bash_profile` — needed
before `kiosk/setup-kiosk.sh` will run). Re-run any time; every step is
idempotent.

## Bringing each app up

### homeassistant

Home automation. Moved here from the pre-restructure percolator build —
see `docker-compose.yml`'s own header comment for exactly what changed
(no Traefik/Authelia in front of it here, unlike the old placement).

```sh
sudo mkdir -p /srv/data/homeassistant /srv/data/postgres-homeassistant
./compose.sh homeassistant up -d
```

Onboarding wizard at `http://${MOCHAPOT_LAN_IP}:8123` on first visit, no
default credentials. **Two manual `configuration.yaml` steps after first
boot**, neither settable via compose (see the compose file's own comments
for exact syntax): pointing the recorder at Postgres instead of the
default SQLite, and setting `recorder.purge_keep_days`/excludes *before*
any ESPHome sensors get added (`infrastructure.md` §9 — diagnostic
entities update constantly and nobody ever reads them).

### musicassistant

```sh
sudo mkdir -p /srv/data/musicassistant
./compose.sh musicassistant up -d
```

No setup beyond bring-up. `network_mode: host`, same as Home Assistant —
needed for mDNS/UPnP player discovery; every target device must be on the
same flat LAN (no VLANs) for this to actually find them.

### pihole

```sh
sudo mkdir -p /srv/data/pihole/etc-pihole
./compose.sh pihole up -d
```

Admin UI at `http://${MOCHAPOT_LAN_IP}:8081/admin` (moved off 80 —
mochaPot's own Traefik now owns 80/443, see "traefik" below), real login (unlike sieve's
copy of this same image — see `pihole/docker-compose.yml`'s own comment
for why: no Traefik/Authelia gate exists on this node). **Never enable
Settings → DHCP here** — see "Why mochaPot" above; this is load-bearing,
not a style preference.

Point some (not all — keep it independent, see below) of the household's
devices at `${MOCHAPOT_LAN_IP}` as a secondary DNS server if a client's
own DNS failover is worth testing. `infrastructure.md` §5 is candid that
this failover is weak in practice: "most clients time out on the primary
before trying the secondary, so the experience is slow browsing, not a
clean switch." Real HA would be `keepalived` with a floating IP — not
attempted here.

### traefik

```sh
sudo mkdir -p /srv/data/traefik/acme
./compose.sh traefik up -d
sudo docker logs traefik --tail 50   # look for a successful cert issuance
```

**Bring pihole (or homeassistant/musicassistant) up before traefik**, per
this README's order — pihole's `network_mode: host` webserver moved off
port 80 specifically so it wouldn't collide with this. If `traefik` still
fails with "address already in use" on 80/443, check `sudo ss -tlnp | grep
':80\|:443'` for whatever else grabbed it first.

Needs `traefik/secrets.env.local`'s `CF_DNS_API_TOKEN` and
`TRAEFIK_ACME_EMAIL` in `.env.local`. Add Local DNS Records in sieve's
Pi-hole for `homeassistant.${DOMAIN}`, `music.${DOMAIN}`, and
`pihole-mochapot.${DOMAIN}`, all pointing at `${MOCHAPOT_LAN_IP}`. Also
needs mochaPot added to percolator's `FORWARD_AUTH_CLIENTS`/`firewall.sh`
(done 2026-09-16) for ForwardAuth to actually answer. Until DNS records
exist, use each app's direct port — see "Traefik and the native-login
backdoor" above. **Set `trusted_proxies` in Home Assistant's `configuration.yaml`**
(see `homeassistant/docker-compose.yml`'s own comment) or it will reject
requests arriving through this Traefik.

### komodo-periphery / scrutiny-collector

```sh
mkdir -p komodo-periphery/keys
# copy cellar:/srv/data/komodo/keys/core.pub to komodo-periphery/keys/core.pub by hand
./compose.sh komodo-periphery up -d
./compose.sh scrutiny-collector up -d
```

Both are fleet agents, not household-facing apps — no Traefik route, no
login of their own. Confirm `MOCHAPOT_DISK_DEVICE` in `.env.local` against
`lsblk -d -o NAME,TYPE,SIZE,MODEL` before bringing `scrutiny-collector` up.
See each file's own header comment for what's still unverified.

### kiosk

See `kiosk/README.md` for the full setup and design notes. In short:

```sh
./render-configs.sh              # renders kiosk/bash_profile
sudo ./kiosk/setup-kiosk.sh
```

Host-native (cage + Chromium, autologin on tty1 as a dedicated `kiosk`
user) — not a container, not routed through any of the apps above except
by pointing `KIOSK_URL` (in `.env.local`) at whichever one's dashboard
should actually be on the wall.

## What's here now

- `compose.sh` — wrapper so every app's `docker-compose.yml` sees the
  shared `.env.local` plus its own `secrets.env.local`, and ensures
  `mochapot_net` exists (unused by homeassistant/musicassistant/pihole —
  all `network_mode: host` — but `traefik` joins it for parity with every
  other node's compose.sh).
- `render-configs.sh` — renders `*.template` files, including
  `kiosk/bash_profile.template` and `traefik/config/*.template`. Copied
  verbatim, generic across the fleet.
- `setup-secrets.sh` — first-time-setup script.
- `generate-secrets.sh` — generates mochaPot's own secrets: Home
  Assistant's recorder DB credentials, Pi-hole's real web password,
  Traefik's Cloudflare token. Music Assistant and kiosk need none.
- `local.env.example` — copy to `.env.local` and fill in:
  `MOCHAPOT_LAN_IP`, `TZ`, `DOMAIN`, `KIOSK_URL`, `PERCOLATOR_LAN_IP`,
  `TRAEFIK_ACME_EMAIL`.
- `.gitignore` — same rules as every other node's.
- `homeassistant/`, `musicassistant/`, `pihole/` — one
  `docker-compose.yml` each, all `network_mode: host`, all carrying
  Traefik labels with an explicit `loadbalancer.server.url` (the
  auto-discovery a bridge-networked app gets doesn't work for host
  networking).
- `traefik/` — reverse proxy + real TLS, with the ForwardAuth middleware
  definition in `config/dynamic.yml.template`. See "Traefik and the
  native-login backdoor" above.
- `kiosk/` — host-native setup script + `.bash_profile` template, no
  compose file.

## Known gaps / things to double-check before relying on this

- **Traefik's ForwardAuth route now works.** mochaPot is registered in
  percolator's `FORWARD_AUTH_CLIENTS` as of 2026-09-16 (none of its apps
  are admin-only, so they use Authelia's household catch-all rule, not
  the admin-host list). Still 502/504s until `sudo ./firewall.sh` has
  actually been run on both mochaPot and percolator, and until this node
  also has its own `firewall.sh` run (added 2026-09-16 — see below). The
  direct-port backdoor (see "Traefik and the native-login backdoor"
  above) works regardless.
- **No `firewall.sh` existed for this node until 2026-09-16.** homeassistant
  (8123), musicassistant (8095), pihole (53/8081), and traefik (80/443)
  all went un-firewalled before that. `sudo ./firewall.sh` now covers all
  of them, scoped to the LAN. Run it once and after any port change.
- **No local DNS records exist yet** for `homeassistant.${DOMAIN}`,
  `music.${DOMAIN}`, `pihole-mochapot.${DOMAIN}` — until sieve's Pi-hole
  has them, reach these by `https://${MOCHAPOT_LAN_IP}` with a
  cert-mismatch warning (expected), or use the direct ports.
- **Home Assistant's OIDC login (via the community `hass-oidc-auth` HACS
  component, alpha-stage) is not set up here at all** — the pre-restructure
  percolator build had this wired to sieve's Authelia; this rebuild
  doesn't, both because that component was already flagged alpha-stage
  before the move and because Traefik's own ForwardAuth (see above) covers
  the SSO gate at the proxy layer instead. Local HA login is the only
  in-app way in for now, and is also the deliberate backdoor.
- **Home Assistant's recorder stays on SQLite until the manual
  `configuration.yaml` step above is done.** The Postgres container and
  credentials exist and are healthy either way — HA just isn't using them
  until that file is edited by hand.
- **Pi-hole's independence from sieve's instance is untested.** Both run
  the same blocklists and upstream resolver by convention, not by any
  actual sync mechanism — a blocklist change on one does not propagate to
  the other. If that divergence ever matters, it needs its own decision,
  not assumed away here.
- **`network_mode: host` containers freeze their DNS servers at creation
  time, forever, until force-recreated.** Found 2026-09-17: Home
  Assistant's `hass-oidc-auth` discovery request failed with "Name does
  not resolve" from inside the container even though `dig`/`curl` for the
  same hostname worked fine on mochaPot's host. Cause: Docker snapshots
  `/etc/resolv.conf` once into the container at creation — it is not a
  live view of the host's file, host-network mode or not. This container
  was created while mochaPot was still on bootstrap DNS
  (`1.1.1.1`/`9.9.9.9`, per `init/purrbrews-init.env.example`) and never
  recreated after the host switched to sieve's Pi-hole, so it kept
  querying public resolvers that don't know this fleet's split-horizon
  records. Fixed with `./compose.sh homeassistant up -d --force-recreate`
  (restart alone does not re-snapshot the file). `pihole` and
  `musicassistant` are `network_mode: host` too and were likely created in
  the same window — recreate them the same way if either ever fails to
  resolve something. General rule for this node: any time its upstream DNS
  server changes, force-recreate every `network_mode: host` container on
  it.
- **Kiosk crash recovery is unverified** — see `kiosk/README.md`'s own
  "Known gaps".
- **Komodo Periphery and Scrutiny collector added 2026-09-16** — see
  `komodo-periphery/` and `scrutiny-collector/`. `stacks/_templates/
  komodo-periphery/` never actually landed in this repo, so both were
  built straight from cellar's own Komodo/Scrutiny blocks instead (same as
  every other node). `komodo-periphery/keys/core.pub` still needs copying
  from cellar by hand before `./compose.sh komodo-periphery up -d` will
  actually connect — see that file's own header comment.
