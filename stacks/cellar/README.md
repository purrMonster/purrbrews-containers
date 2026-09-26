# cellar

**The dump store, file shares and the fleet's ops tools**: `192.168.0.12`, ThinkCentre
M710q (i3-7100T, 8 GB), NVMe for the OS and the dump store, plus an old 1 TB HDD
that no longer holds backups.

cellar is always on, so anything that has to run on a schedule, and be noticed
when it doesn't, lives here.

| App | URL | What it's for |
|---|---|---|
| [Komodo](komodo/) | `komodo.${DOMAIN}` (admins), or `:9120` | Container management for the whole fleet (Core, Mongo, cellar's own agent) |
| [Scrutiny](scrutiny/) | `scrutiny.${DOMAIN}` (admins), or `:8080` | SMART disk health; the hub every node's collector reports to |
| [Traefik](traefik/) | — | HTTPS for the two above |
| [Samba](smb/) | `\\cellar\household`, `\\cellar\archive` | File shares. Built, not in use yet (no firewall rule) |
| [NFS](nfs/README.md) | `cellar:/srv/media/archive` | Archive export, host-native. Nothing mounts it yet |
| [restic](restic/README.md) | — | The backup chain's hub, host-native: the dump store, waking roastery, the Drive copy, the morning check. Scripts written, not switched on yet |

## Setup

As `barista` in `/opt/purrbrews/stacks/cellar`, after `init/purrbrews-init.sh cellar`:

```bash
./setup-secrets.sh      # asks for DOMAIN, TRAEFIK_ACME_EMAIL, the two disks, the
                        # Cloudflare token and the Drive client; generates the rest
sudo ./firewall.sh      # LAN → 80/443 (Traefik), 9120 (Komodo), 8080 (Scrutiny)
```

Then, in order (`node.conf`), checking each before the next:

| # | Command | Check |
|---|---|---|
| 1 | `./compose.sh komodo up -d` | `sudo docker logs komodo-core` starts clean; log in at `http://192.168.0.12:9120` as `barista` with `KOMODO_INIT_ADMIN_PASSWORD` from `komodo/secrets.env.local` |
| 2 | `./compose.sh scrutiny up -d` | both disks listed at `http://192.168.0.12:8080` |
| 3 | `./compose.sh traefik up -d` | certificates issued in `sudo docker logs traefik`; `https://komodo.${DOMAIN}` asks for an Authelia login |
| 4 | `./compose.sh smb up -d` | only when the shares are wanted; add the rule in `smb/firewall` first |
| — | `sudo ./nfs/setup-nfs.sh`, then [restic/README.md](restic/README.md) | host-native, whenever needed |

`./compose.sh --all up -d` does 1–4 in that order once everything has been up once.

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
| `/srv/data/traefik/acme` | certificates | no, re-issued |
| `/srv/dumps/<node>` | every node's database dumps (the dump store) | yes, as the `dumps` snapshot (`backup.sh store`) |
| `/srv/media/{household,archive}` | the shares | yes, once they hold anything |

## Known gaps

- **Nothing is backed up yet.** The scripts are written (runbook, 2026-09-27) but
  not tied together: roastery's backup target, the keys, the timers and a
  restore test are still to do. [restic/README.md](restic/README.md) has the order.
- **Samba isn't reachable**: ufw-docker keeps 139/445 closed until `smb/firewall`
  gets its rule. Pin its image when it goes into use.
