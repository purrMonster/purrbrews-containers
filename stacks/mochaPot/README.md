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

All three apps' host-networked ports (`8123`, `8095`, `80`) stay published
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

Admin UI at `http://${MOCHAPOT_LAN_IP}/admin`, real login (unlike sieve's
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
docker logs traefik --tail 50   # look for a successful cert issuance
```

Needs `traefik/secrets.env.local`'s `CF_DNS_API_TOKEN` and
`TRAEFIK_ACME_EMAIL` in `.env.local`. Add Local DNS Records in sieve's
Pi-hole (once sieve exists in this repo) for `homeassistant.${DOMAIN}`,
`music.${DOMAIN}`, and `pihole-mochapot.${DOMAIN}`, all pointing at
`${MOCHAPOT_LAN_IP}`. Until then, or until percolator's Authelia exists,
use each app's direct port — see "Traefik and the native-login backdoor"
above. **Set `trusted_proxies` in Home Assistant's `configuration.yaml`**
(see `homeassistant/docker-compose.yml`'s own comment) or it will reject
requests arriving through this Traefik.

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

- **Traefik's ForwardAuth route won't actually work yet.** It depends on
  percolator's Authelia, which now exists in this repo, but mochaPot isn't
  registered with it yet — its IP still needs adding to percolator's
  `FORWARD_AUTH_CLIENTS`/`firewall.sh` and to Authelia's admin-host list
  (tracked in `runbook.md`'s backlog). Until then, every `*.${DOMAIN}`
  hostname on this node will 502/504 through Traefik. The direct-port
  backdoor (see "Traefik and the native-login backdoor" above) is what
  actually works today.
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
- **Kiosk crash recovery is unverified** — see `kiosk/README.md`'s own
  "Known gaps".
- **No Komodo Periphery agent yet.** Unlike the pre-restructure mochaPot,
  this rebuild doesn't pre-emptively scaffold one — cellar's Komodo Core
  exists now (see `stacks/cellar/`), so add mochaPot's own Periphery from
  `stacks/_templates/komodo-periphery/` (once that template is migrated
  into this repo) when fleet-wide container management for this node is
  actually wanted, not before.
