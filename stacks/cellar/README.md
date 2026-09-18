# cellar

Backup target, file storage, and fleet ops node — 192.168.0.12, ThinkCentre
M710q (i3-7100T, 8 GB RAM, 256 GB M.2 NVMe + 1 TB 2.5" HDD). See
`infrastructure.md` §2-3 for the full fleet hardware table.

This stack directory was **rebuilt from scratch on 2026-09-16** for the
post-restructure fleet — it is not a migration of the pre-restructure
`purrBrews-infra` cellar build, even though several files below were
adapted from it. Treat everything here as a new project: nothing is assumed
to already be running, no `.env.local` or `secrets.env.local` carries over,
and every setup step below starts from a bare Debian 13 node that has
already been through `init/purrbrews-init.sh`.

**cellar runs five things**, per `infrastructure.md` §4, plus its own
Traefik added 2026-09-16 so `komodo` and `scrutiny` get real HTTPS on
pretty hostnames instead of bare LAN IP:port:

| App | What it does |
|---|---|
| [restic](#restic) | Versioned, encrypted, deduplicated backups — the fleet's actual backup target |
| [smb](#smb) / [nfs](#nfs) | File shares — household + app archives |
| [scrutiny](#scrutiny) | S.M.A.R.T. disk health, **hub** for the whole fleet |
| [komodo](#komodo) | Fleet-wide container management — **Core + Mongo**, plus cellar's own agent |
| [traefik](#traefik) | Reverse proxy + real TLS for komodo/scrutiny, with a native-login backdoor |

Two apps that lived on the pre-restructure cellar are **gone from this
node**, not lost: Vaultwarden and Caddy moved to `percolator` per
`infrastructure.md` §4's app table (ingress and identity now sit together
with the apps that need them). Nothing below tries to recreate them here.

## Why cellar, specifically

- **The schedule lives here, not on roastery.** `infrastructure.md` §7: "A
  mirror that did not run must be visible from an always-on box rather than
  failing silently on a machine nobody logged into." cellar is always on;
  roastery sleeps.
- **Scrutiny's hub moved here** (it lived on `silo` pre-restructure, which
  no longer exists as a role — see the 2026-09-15 private notes). cellar
  already has two physical disks worth monitoring and is the natural place
  for every other node's `scrutiny-collector` to report to.
- **Komodo Core + Mongo moved here too**, same reasoning — `silo`'s split
  duties are now shared between `sieve` (network/alerting) and `cellar`
  (storage/ops), per `infrastructure.md` §1's retirement note for `silo`.

## Traefik and the native-login backdoor

Every node in this rebuild now runs its own Traefik, not a shared one —
cellar's fronts `komodo` and `scrutiny` only (the two apps here with an
HTTP UI worth a pretty hostname; `smb`/`nfs` aren't HTTP, and
`restic` isn't a container). Real TLS via Cloudflare DNS-01, same
mechanism the pre-restructure fleet's Traefik/Caddy instances all used
(no port 80 exposed to the internet at all — CGNAT, no port forward — so
DNS-01 is the only option regardless).

**The backdoor is deliberate, not an oversight**: every app's own host
port (`9120` for Komodo, `8080` for Scrutiny) stays published alongside
the Traefik route. The pretty hostname (`komodo.${DOMAIN}`,
`scrutiny.${DOMAIN}`) goes through Traefik's `authelia-forwardauth`
middleware — percolator's Authelia has to be up and reachable for that
path to work. The direct `http://${CELLAR_LAN_IP}:<port>` path bypasses
Traefik and Authelia entirely and lands straight on the app's own native
login (Komodo's local admin account; Scrutiny has none at all, see
"Known gaps"). If percolator is down, or Traefik itself is down, the
backdoor still works — that's the whole point of keeping both paths open
rather than routing everything exclusively through Traefik the way
sieve's pre-restructure Pi-hole did.

## First-time setup on cellar

```sh
cd /opt/purrbrews/stacks/cellar
./setup-secrets.sh
```

This creates `.env.local` from `local.env.example`, prompts for every
`REPLACE_ME` (LAN IP, disk devices — confirm both with `lsblk -d -o
NAME,TYPE,SIZE,MODEL`, don't trust the table above blindly on a node that
hasn't been re-imaged since the restructure), runs `generate-secrets.sh`,
then `render-configs.sh`. Re-run any time; every step is idempotent.

Then bring up each containerized app in whatever order is convenient —
none of the six below depend on each other at the compose level (Komodo's
three services are one compose project and start together). Recommended
order below follows what unblocks other nodes soonest: **komodo first**
(so cellar shows up as a Server before any other node's Periphery agent
needs to connect to it), then **scrutiny** (so other nodes' future
collectors have somewhere to push to), then **traefik** (so both get real
hostnames), then smb/nfs/restic in any order. Run `sudo
./firewall.sh` (added 2026-09-16) once every app that needs a rule is up
— it opens 80/443 (traefik), 9120 (komodo), and 8080 (scrutiny) to the
LAN and nothing else.

## Bringing each app up

### komodo

Fleet-wide container management. Core + Mongo run on cellar now (moved
from the pre-restructure `silo`); cellar also runs its own Periphery agent
in the same compose project so Core can manage cellar's own containers,
not just remote ones.

```sh
sudo mkdir -p /srv/data/komodo/{mongo-data,mongo-config,keys,backups}
./compose.sh komodo up -d
docker logs komodo-core --tail 50   # look for a clean startup, not a Mongo AVX crash
```

**Before first bring-up**, confirm cellar's CPU actually supports AVX
(`grep avx /proc/cpuinfo`) — MongoDB 5.0+ requires it and crashes outright
without it. See `komodo/docker-compose.yml`'s own header comment for the
FerretDB fallback if it's missing.

Log in at `http://${CELLAR_LAN_IP}:9120` with `barista` /
`KOMODO_INIT_ADMIN_PASSWORD` (printed by `generate-secrets.sh`, also in
`komodo/secrets.env.local`). **No OIDC login, by decision** — percolator's
Authelia exists and could federate this, but 2026-09-16's call was local
auth only for now. See "Known gaps" below.

Once a future node's own Periphery agent needs to connect here: an
onboarding key comes from Komodo's UI (Settings → the onboarding/servers
section), and `core.pub` needs copying from `/srv/data/komodo/keys/core.pub`
on cellar to that node — same pattern the pre-restructure fleet already
proved out (percolator/sieve/cellar all connected to the old silo-hosted
Core this same way on 2026-09-05).

### scrutiny

S.M.A.R.T. disk health, running as the fleet's **hub** for the first time
on this node (moved from the pre-restructure `silo`). Monitors cellar's
own NVMe and HDD directly; every other migrated node's `scrutiny-collector`
pushes to it over the LAN.

```sh
sudo mkdir -p /srv/data/scrutiny/{config,influxdb}
./compose.sh scrutiny up -d
```

Confirm `CELLAR_DISK_DEVICE_NVME`/`_HDD` in `.env.local` against real
hardware first (`lsblk -d -o NAME,TYPE,SIZE,MODEL`; for the NVMe use the
controller node `/dev/nvme0`, not the namespace block device
`/dev/nvme0n1`). Dashboard at `http://${CELLAR_LAN_IP}:8080` — no login,
see "Known gaps".

### smb

Household + app-archive file shares over Samba.

```sh
sudo mkdir -p /srv/media/household /srv/media/archive
./compose.sh smb up -d
```

One user, `barista`, password in `smb/secrets.env.local`. Add real
household accounts with more `ACCOUNT_<name>`/`UID_<name>` env vars as
needed — not done here, this is a starting point, same as the
pre-restructure build left it.

### nfs

Host-native, not a container — see `nfs/README.md` and
`nfs/setup-nfs.sh`'s own header comment for why. Exports
`/srv/media/archive` for percolator/mochaPot to mount once they're
migrated into this repo and actually need to.

```sh
sudo ./nfs/setup-nfs.sh
```

### traefik

```sh
sudo mkdir -p /srv/data/traefik/acme
./compose.sh traefik up -d
docker logs traefik --tail 50   # look for a successful cert issuance, not just a clean startup
```

Needs `traefik/secrets.env.local`'s `CF_DNS_API_TOKEN` (prompted by
`setup-secrets.sh`/`generate-secrets.sh`, same Cloudflare token every
other node's Traefik/Caddy in this fleet uses) and `TRAEFIK_ACME_EMAIL`
in `.env.local`. **Add Local DNS Records in sieve's Pi-hole** (once
sieve exists in this repo) for `komodo.${DOMAIN}` and
`scrutiny.${DOMAIN}`, both pointing at `${CELLAR_LAN_IP}` — not added
automatically, not part of this bring-up. Until then, or until
percolator's Authelia exists, use each app's direct port — see "Traefik
and the native-login backdoor" above.

### restic

The fleet's actual backup target — not a container, a set of scripts +
systemd timers, same "no well-maintained option exists as a container for
this job" reasoning the pre-restructure `backup-mirror/` used, but this
time the scripts actually work end to end rather than defining a function
nobody ever called.

```sh
sudo mkdir -p ${CELLAR_HDD_MOUNT:-/srv/backup}
./restic/restic-init.sh          # one-time repository creation
sudo cp restic/restic-backup.service restic/restic-backup.timer \
        restic/restic-prune.service restic/restic-prune.timer \
        /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer restic-prune.timer
```

`restic/restic-backup.sh` has **no sources configured yet** — same
"REPLACE_ME until a node actually has something worth backing up" state
the pre-restructure `mirror.sh` was in, except this version is a real,
runnable `restic backup` call per source, not a function definition that
was never called (see the 2026-09-13 fleet audit, Tier 0 #1 — that's
exactly the bug being fixed by not repeating its shape). Uncomment and
fill in each source in the script as percolator/sieve/mochaPot get real
data worth a backup, once they're migrated into this repo.

**roastery mirror and Google Drive sync are scaffolded but not enabled**
— `restic/mirror-to-roastery.sh` and `restic/drive-sync.sh` both refuse to
run until `ROASTERY_WOL_MAC`/`ROASTERY_SSH_HOST`/`ROASTERY_MIRROR_PATH`
(mirror) and a rendered `rclone.conf` + one interactive `rclone config
reconnect` (Drive sync) exist. Wire these up once there's a real backup in
the local repository worth mirroring off cellar. The mirror is plain SSH/WoL
and needs no further setup beyond those three variables; Drive sync needs
its own Google API client and an OAuth handshake, walked through below.

#### Setting up Google Drive sync

`generate-secrets.sh` prompts for `RCLONE_DRIVE_CLIENT_ID` and
`RCLONE_DRIVE_CLIENT_SECRET` — these are **not generated, only pasted in**,
because they identify *your own* Google API client rather than a secret
cellar can invent. `infrastructure.md` §7 is explicit about why this step
can't be skipped: rclone's built-in shared client is the single biggest
cause of `403 userRateLimitExceeded`, since every rclone user on earth
shares its quota. This is a one-time setup, not a per-node one — the same
client ID/secret can be reused if you ever add a second Drive-backed node.

1. **Create the API client**, at [console.cloud.google.com](https://console.cloud.google.com):
   - New project (anything, e.g. `purrbrews-restic`).
   - *APIs & Services → Library* → enable the **Google Drive API** for that
     project.
   - *APIs & Services → OAuth consent screen* → User type **External** →
     fill in an app name and your own email, add your own Google account
     under **Test users**. Leave the app in **Testing** status — it never
     needs Google's verification review since only you will ever use it;
     the only cost of staying in Testing is that OAuth tokens expire after
     7 days unless refreshed, which rclone does automatically as long as
     it keeps running.
   - *APIs & Services → Credentials → Create Credentials → OAuth client
     ID* → Application type **Desktop app** → any name.
   - Copy the **Client ID** and **Client secret** it shows you — that's
     the only time the secret is displayed in full.

2. **Paste them in.** Run (or re-run) `./setup-secrets.sh` on cellar and
   answer the two prompts with the values from step 1. This writes them
   into `restic/secrets.env.local` and, via `render-configs.sh`, into a
   freshly rendered `restic/rclone.conf` (from `rclone.conf.template`) —
   the `[drive]` remote's `client_id`/`client_secret` lines.

3. **Authorize the OAuth token itself.** This is the part rendering can't
   do — Google's consent screen has to be clicked through in an actual
   browser, and cellar is headless. `rclone config reconnect drive:
   --config restic/rclone.conf` will print a localhost URL and wait,
   which is useless over a plain SSH session since nothing on your laptop
   can reach cellar's loopback. Two ways around that:
   - **SSH tunnel (simplest):** connect with the OAuth callback port
     forwarded —
     ```sh
     ssh -L 53682:localhost:53682 barista@cellar
     ```
     then, in that same session:
     ```sh
     cd /opt/purrbrews/stacks/cellar
     rclone config reconnect drive: --config restic/rclone.conf
     ```
     It prints a `http://127.0.0.1:53682/auth?...` link — open that exact
     link in a browser on your own machine (the tunnel carries Google's
     redirect back to cellar's rclone). Log in, grant access, done.
   - **No tunnel available:** run the authorization on a *different*
     machine that has a browser and rclone installed (your laptop,
     roastery), using the same client ID/secret from step 1:
     ```sh
     rclone authorize "drive" '<RCLONE_DRIVE_CLIENT_ID>' '<RCLONE_DRIVE_CLIENT_SECRET>'
     ```
     It opens a browser, you approve access, and it prints a
     `config_token`-style JSON blob to the terminal. Then on cellar:
     ```sh
     rclone config reconnect drive: --config restic/rclone.conf --auth-no-open-browser
     ```
     and paste that JSON blob in when prompted.

4. **Set the crypt layer's password**, once `drive:` itself is connected —
   `drive-crypt` (the remote everything actually reads/writes) wraps
   `drive:` so file names and folder structure are hidden from Google too,
   on top of restic's own content encryption:
   ```sh
   rclone config password drive-crypt password  --config restic/rclone.conf
   rclone config password drive-crypt password2 --config restic/rclone.conf
   ```
   Each prompts for a value — say `y` when it offers to generate a random
   one rather than typing your own. **Both values must reach `flask`**
   alongside `RESTIC_PASSWORD` (`infrastructure.md` §8): lose them and the
   local repository is still fine, but everything already pushed to Drive
   is unreadable, since the crypt layer's password isn't stored anywhere
   Google-side or recoverable from `rclone.conf` alone.

5. **Confirm it actually works** before trusting it:
   ```sh
   rclone lsd drive-crypt: --config restic/rclone.conf
   ```
   An empty listing (or a clean "directory not found") means auth and the
   crypt layer both work; an OAuth error means step 3 needs redoing, and a
   `403` means step 1's client isn't actually being used (check
   `rclone.conf`'s `[drive]` section still has real values, not
   `${RCLONE_DRIVE_CLIENT_ID}` unsubstituted).

6. **Enable the timer**, once there's a real local backup worth mirroring
   off cellar (see the "no sources configured yet" note above):
   ```sh
   sudo cp restic/drive-sync.service restic/drive-sync.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now drive-sync.timer
   ```
   It runs nightly at 05:00, after the roastery mirror. A failed run
   notifies `NTFY_URL` if set — check `journalctl -t
   cellar-restic-drive-sync` either way the first few times.

**The repository passphrase (`RESTIC_PASSWORD`) must reach `flask`
by hand** — `generate-secrets.sh` prints a reminder after it generates
one. `infrastructure.md` §7: "Encrypted cloud backup whose key sits only
on the machine that died is not a backup."

## What's here now

- `compose.sh` — wrapper so every app's `docker-compose.yml` sees the
  shared `.env.local` plus its own `secrets.env.local`, and ensures
  `cellar_net` exists. Same mechanics as every other node's `compose.sh`.
- `render-configs.sh` — renders `*.template` files into their real
  counterparts. Copied verbatim, generic across the fleet.
- `setup-secrets.sh` — first-time-setup script: creates `.env.local`,
  prompts for `REPLACE_ME` values, runs `generate-secrets.sh` then
  `render-configs.sh`.
- `generate-secrets.sh` — generates cellar's own secrets, locally, right
  here, straight into each app's `secrets.env.local`. Covers smb, komodo,
  and restic (including the rclone Google Drive client) as of this
  rebuild.
- `local.env.example` — copy to `.env.local` and fill in:
  `CELLAR_LAN_IP`, `TZ`, `DOMAIN`, `CELLAR_DISK_DEVICE_NVME`,
  `CELLAR_DISK_DEVICE_HDD`, `CELLAR_HDD_MOUNT`, `PERCOLATOR_LAN_IP`,
  `TRAEFIK_ACME_EMAIL`.
- `.gitignore` — `.env.local`, `*/secrets.env.local`, rendered
  `*/config/*` (except tracked `.template` sources), restic's local cache,
  and the rendered `rclone.conf` are never committed.
- `komodo/`, `scrutiny/`, `smb/` — one `docker-compose.yml` each,
  all joined to the external `cellar_net` network `compose.sh` creates.
  `komodo`/`scrutiny` also carry Traefik labels.
- `nfs/` — host-native setup script, no compose file.
- `restic/` — init/backup/prune/mirror/drive-sync scripts, their systemd
  service+timer pairs, and the rclone config template.
- `traefik/` — reverse proxy + real TLS for `komodo`/`scrutiny`, with the
  ForwardAuth middleware definition in `config/dynamic.yml.template`. See
  "Traefik and the native-login backdoor" above.

## Known gaps / things to double-check before relying on this

- **Real hardware unconfirmed.** `infrastructure.md` §3's "256 GB NVMe +
  1 TB HDD" is the post-restructure design, not something re-verified on
  this specific physical node since the rebuild — the pre-restructure
  cellar's own `lsblk` (2026-09-05) found no HDD at all, just a 238.5 GB
  SATA SSD and a 476.9 GB NVMe. Run `lsblk -d -o NAME,TYPE,SIZE,MODEL`
  before trusting `local.env.example`'s device names.
- **Komodo has no OIDC login, by decision.** percolator's Authelia
  exists and could federate it, but 2026-09-16's call was to keep Komodo
  on local auth only for now (see `komodo/docker-compose.yml`'s header
  comment) — not a migration gap, a decision that could be reopened
  later if local auth becomes a real papercut.
- **Traefik's ForwardAuth route now works.** cellar is registered in
  percolator's `FORWARD_AUTH_CLIENTS`/`firewall.sh` and in Authelia's
  admin-host list as of 2026-09-16. `komodo.${DOMAIN}`/
  `scrutiny.${DOMAIN}` will still 502/504 until `sudo ./firewall.sh` has
  actually been **run** on both cellar and percolator (this repo can't
  run it for you), and until sieve's Pi-hole has Local DNS Records for
  both hostnames pointing at `${CELLAR_LAN_IP}`.
- **Scrutiny and Komodo have zero native auth of their own beyond what
  ForwardAuth adds.** `firewall.sh` (added 2026-09-16) scopes 8080/9120
  to the LAN via `ufw route allow` (Docker's iptables DNAT bypasses plain
  `ufw` for any published bridge-network port — `infrastructure.md`
  §5/§9), but that only restricts *who on the LAN* can reach them, not
  *whether they need a password once there* — Scrutiny has none at all,
  Komodo has its own local admin login. Accepted on a trusted LAN, same
  call the pre-restructure fleet made repeatedly for the same underlying
  gap. smb isn't built yet (see below), so it has no `firewall.sh` rule.
- **restic has no sources configured.** The repository will exist and be
  empty until real source paths are uncommented in
  `restic/restic-backup.sh` — don't assume a backup exists just because
  the timer is enabled. Check `restic -r "$CELLAR_HDD_MOUNT/restic-repo"
  snapshots` for real.
- **roastery mirror and Drive sync are unwired.** See restic's
  bring-up section above.
- **`smb/` is documented above but doesn't exist in this repo yet.** This
  README's "smb" section and app table both describe it as buildable
  (`./compose.sh smb up -d`, a `barista` user, a password in
  `smb/secrets.env.local`), but no `stacks/cellar/smb/docker-compose.yml`
  has actually been written — confirmed missing during the 2026-09-16
  repass (`komodo`/`scrutiny`/`traefik` all exist; `smb` does not).
  Needs a decision on share paths/permissions before it can be built, not
  something to fill in with a guess — flagged, not fixed, in this pass.
- **UID/GID between smb and nfs not reconciled against a real consumer.**
  Both assume UID 1000 (`barista`'s UID fleet-wide); neither has been
  tested against an actual mounting client yet since none exists in this
  repo.
- **No node has migrated into this repo yet except cellar/mochaPot/grinder
  and the fleet-level `init/`/`bootstrap/` pieces** — `sieve`'s ntfy (for
  the `NTFY_URL` the restic scripts optionally use), Pi-hole (for the
  Local DNS Records `komodo.${DOMAIN}`/`scrutiny.${DOMAIN}` need), and
  `percolator`'s Authelia don't exist here yet. Every reference to them
  above is forward-looking, not something to expect working today.
- **No local DNS records exist for `komodo.${DOMAIN}`/`scrutiny.${DOMAIN}`
  yet** — until sieve's Pi-hole has them, reach both by
  `https://${CELLAR_LAN_IP}` with a cert-mismatch warning (expected —
  Traefik's cert is issued for the real hostname, not the bare IP), or
  just use the direct ports.
