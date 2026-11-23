# cellar

> **Carried over from the pre-move fleet (2026-11-16).** This page was written for
> the old layout and hardware. Paths and addresses were updated mechanically; the
> bring-up notes are still the best record of how this node's apps fit together,
> but check each step against [`docs/migration-plan.md`](../../docs/migration-plan.md)
> and [`docs/hardware.md`](../../docs/hardware.md) before relying on it.

**Backups, the fleet's ops tools and Home Assistant**: `192.168.1.12`, ThinkCentre
M710q (i3-7100T, 16 GB): a 256 GB SATA SSD for the OS, and the 1 TB NVMe as `/srv`
for the dump store and the restic repository ([docs/hardware.md](../../docs/hardware.md)).

cellar is always on, so anything that has to run on a schedule, and be noticed
when it doesn't, lives here. Home Assistant moved here from mochaPot on
2026-11-22: built-in Ethernet, the quietest node, and not percolator, so the house
keeps working when sign-in is down.

| App | URL | What it's for |
|---|---|---|
| [Komodo](../../stacks/fleet-management/komodo/) | `komodo.${DOMAIN}` (admins), or `:9120` | Container management for the whole fleet (Core, Mongo, cellar's own agent) |
| [Scrutiny](../../stacks/fleet-management/scrutiny/) | `scrutiny.${DOMAIN}` (admins), or `:8080` | SMART disk health; the hub every node's collector reports to |
| [Home Assistant](../../stacks/home/homeassistant/README.md) | `homeassistant.${DOMAIN}`, or `:8123` | Home automation and the voice assistants' brain; signs in with Authelia itself (OIDC), local account as the break-glass |
| [Traefik](../../stacks/network/traefik/) | — | HTTPS for the three above, and persianPerch |
| [persianPerch](../../stacks/fleet-management/persian-perch/) | `perch.${DOMAIN}` (admins) | The fleet's watcher: containers, backups, disks, endpoints, files dropped, the house. Read-only; alerts to ntfy |
| [Samba](../../stacks/backup/smb/) | `\\cellar\household`, `\\cellar\archive` | File shares. Built, not in use yet (no firewall rule) |
| [NFS](../../stacks/backup/nfs/README.md) | `cellar:/srv/media/archive` | Archive export, host-native. Nothing mounts it yet |
| [restic](../../stacks/backup/restic/README.md) | — | The backup chain's hub, host-native: the dump store, waking roastery, the Drive copy, the morning check. On since 2026-09-28; roastery's repository to restore after its 2026-10-07 wipe |

## Setup

As `barista` in `/opt/purrbrews/nodes/cellar`, once the node is set up (`docs/migration-plan.md`, phase 1):

```bash
./setup-secrets.sh      # asks for DOMAIN, TRAEFIK_ACME_EMAIL, the two disks, the
                        # Cloudflare token and the Drive client; generates the rest
sudo ./firewall.sh      # LAN → 80/443 (Traefik), 9120 (Komodo), 8080 (Scrutiny), 8123 (Home Assistant)
```

Then, in order (`node.conf`), checking each before the next:

| # | Command | Check |
|---|---|---|
| 1 | `./compose.sh komodo up -d` | `sudo docker logs komodo-core` starts clean; log in at `http://192.168.1.12:9120` as `barista` with `KOMODO_INIT_ADMIN_PASSWORD` from `komodo/secrets.env.local` |
| 2 | `./compose.sh scrutiny up -d` | both disks listed at `http://192.168.1.12:8080` |
| 3 | `./compose.sh traefik up -d` | certificates issued in `sudo docker logs traefik`; `https://komodo.${DOMAIN}` asks for an Authelia login |
| 4 | `./compose.sh homeassistant up -d` | migration plan phase 7, once Authelia exists: onboarding at `http://192.168.1.12:8123`, then the [configuration.yaml steps](../../stacks/home/homeassistant/README.md#configurationyaml) (`trusted_proxies` is `172.30.12.0/24`) |
| 5 | `./compose.sh smb up -d` | only when the shares are wanted; add the rule in `smb/firewall` first |
| 6 | whisper, piper, voice-satellite | migration plan phase 9 ([docs/voice.md](../../docs/voice.md)) |
| 7 | `./compose.sh persian-perch up -d` | its [README](../../stacks/fleet-management/persian-perch/README.md) checklist; read persianPerch's `integration/ROLLOUT.md` before the first run |
| — | `sudo ./nfs/setup-nfs.sh`, then [restic/README.md](../../stacks/backup/restic/README.md) | host-native, whenever needed |

`./compose.sh --all up -d` does 1–7 in that order once everything has been up once.

## Things worth knowing

- **Other nodes' agents need two things from here.** Komodo Periphery on a node
  needs cellar's `/srv/data/komodo/keys/core.pub` copied into its
  `komodo-periphery/keys/`, and an onboarding key from Komodo's UI (Settings →
  onboarding) for its first connect. Scrutiny collectors just need
  `CELLAR_LAN_IP`, which is in `stacks/fleet.env`.
- **Two ways into Komodo and Scrutiny, on purpose.** Through Traefik they sit behind
  Authelia (admins only). The published ports skip Traefik and Authelia, so they
  still work when percolator is down: Komodo has its own login there, Scrutiny has
  none at all. The firewall keeps both ports to the LAN.
- **Komodo is root on every node.** Its Periphery agents have the Docker socket.
  Treat `KOMODO_JWT_SECRET`, `KOMODO_WEBHOOK_SECRET` and the admin password like a
  root SSH key. Registration is off; there's only the one admin.
- **Komodo stays on local login.** Authelia could front it with OIDC, but when
  Authelia is broken Komodo is exactly what I'll want to reach.
- **Mongo 5+ needs AVX.** cellar has it. Check `grep avx /proc/cpuinfo` before
  moving Komodo anywhere else.

## Data

| Path | Contents | Back up |
|---|---|---|
| `/srv/data/komodo/mongo-*` | Komodo's database | yes, as a `mongodump` |
| `/srv/data/komodo/keys` | Core's key pair | yes (every agent trusts `core.pub`) |
| `/srv/data/scrutiny` | SMART history | no |
| `/srv/data/homeassistant` | config, automations, `secrets.yaml` | **yes** |
| `/srv/data/postgres-homeassistant` | recorder history | as a dump, if at all |
| `/srv/data/traefik/acme` | certificates | no, re-issued |
| `/srv/dumps/<node>` | every node's database dumps (the dump store) | yes, as the `dumps` snapshot (`backup.sh store`) |
| `/srv/media/{household,archive}` | the shares | yes, once they hold anything |

## Known gaps

- **Backups after roastery's wipe.** The chain ran from 2026-09-28 (restore tests
  passed 2026-09-29), but roastery, which holds the repository, was wiped on
  2026-10-07. Restore it from Drive before the nodes write again;
  [restic/README.md](../../stacks/backup/restic/README.md) and roastery's `flask/RECOVERY.md` part B.
- **Samba isn't reachable**: ufw-docker keeps 139/445 closed until `smb/firewall`
  gets its rule. Its image is pinned by digest already.
