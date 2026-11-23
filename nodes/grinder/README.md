# grinder

> **Carried over from the pre-move fleet (2026-11-16).** This page was written for
> the old layout and hardware. Paths and addresses were updated mechanically; the
> bring-up notes are still the best record of how this node's apps fit together,
> but check each step against [`docs/migration-plan.md`](../../docs/migration-plan.md)
> and [`docs/hardware.md`](../../docs/hardware.md) before relying on it.

**Automation, AI, photos, files and the self-tracking apps**: `192.168.1.14`, an HP
Pavilion x360 (i5-7200U, 16 GB, one 1 TB WD SN530 NVMe, USB Ethernet; checked
2026-11-23).

Immich and OpenCloud moved here from percolator on 2026-11-23 (owner), onto
the 1 TB disk; Immich sits next to its machine learning. They are the two
household apps on grinder: if grinder is down, photo backup and file sync
wait. Everything else here can be down for an evening without anyone
noticing. Both still sign in through Authelia on percolator.

| App | URL | What it's for |
|---|---|---|
| n8n | `n8n.${DOMAIN}`, or `:5678` | Workflow automation; ties the rest together |
| postgres-vector | — | Postgres + pgvector, the vector store |
| embedding-worker | — | CPU embeddings for n8n, built here (`embedding-worker/Dockerfile`) |
| [Immich](../../stacks/apps/immich/) | `immich.${DOMAIN}` (no direct port) | Photos and videos; its own login and Authelia OIDC |
| [Immich ML](../../stacks/ai/immich-ml/) | — (only on `proxy`) | Faces and smart search for Immich, on the CPU |
| [OpenCloud](../../stacks/apps/opencloud/) | `opencloud.${DOMAIN}` (no direct port) | Files, through Authelia OIDC |
| Open WebUI | `chat.${DOMAIN}`, or `:8081` | Chat with the cloud model through LiteLLM |
| Karakeep | `karakeep.${DOMAIN}`, or `:3030` | Bookmarks and read-it-later |
| FitTrackee | `fittrackee.${DOMAIN}`, or `:5001` | Rides, from the bike computer's GPX |
| Traccar | `traccar.${DOMAIN}`, or `:8082` (phone posts to `:5055`) | Live position of the bike |
| ESPHome | `esphome.${DOMAIN}`, or `:6052` | The ESP32 sensors |
| Speedtest Tracker | `speedtest.${DOMAIN}`, or `:8765` | Hourly ISP speed tests |
| [pourOver](../../stacks/automation/pourover/README.md) | none; `:8790` for Gatus only (optional app) | Text in meowGram, a well-filed task in Vikunja |
| Traefik | — | HTTPS for all of the above, behind Authelia |
| Komodo Periphery | — | Lets Komodo on cellar manage this node's containers |
| Scrutiny collector | — | SMART data for the hub on cellar |

Every app with a UI is behind Authelia on its hostname and keeps its own port open
to the LAN. Unlike on cellar or mochaPot, every one of those ports has a real login
of its own, so the way in when Authelia is down is never an open door.
Immich and OpenCloud are the exceptions: no direct port, only their routes. postgres-vector, the
embedding worker and Immich ML aren't published at all; they're only on `proxy`.

## Setup

As `barista` in `/opt/purrbrews/nodes/grinder`, once the node is set up (`docs/migration-plan.md`, phase 1):

```bash
./setup-secrets.sh      # asks for DOMAIN, TRAEFIK_ACME_EMAIL, roastery's IP, the disk and
                        # the Cloudflare token; generates the rest
sudo ./firewall.sh
./compose.sh --all up -d
```

`--all` goes in `node.conf` order: database and embedding worker first, then the
apps, then Traefik and the agents (copy `komodo-periphery/keys/core.pub` from cellar
first). `compose.sh` creates every data directory before its app starts, including
n8n's, which has to belong to uid 1000 or n8n dies with `EACCES` on every start.

## First visits

| App | What to do |
|---|---|
| n8n | Create the owner account. |
| Open WebUI | The first account made becomes the admin. |
| Karakeep | Set `DISABLE_SIGNUPS: "false"` for the first account, then straight back to `"true"` and `up -d` again. |
| FitTrackee | Create the first account (check whether it becomes admin on this version). |
| Traccar | **Log in as admin/admin and change it at once**; the image won't take it from the environment. |
| ESPHome | User `barista`, `ESPHOME_DASHBOARD_PASSWORD` from `esphome/secrets.env.local`. The 2.4 GHz WPA2-only SSID must exist before the first sensor is flashed. |
| Speedtest Tracker | User `barista` / `SPEEDTEST_TRACKER_ADMIN_PASSWORD`. Confirm in the logs that a test actually ran on the hour; when the schedule isn't picked up it fails silently. |
| embedding-worker | `sudo docker exec embedding-worker curl -s localhost:8000/health` |

## Things worth knowing

- **Backdoor ports and the firewall.** These ports are published by Docker, so the
  UFW rules (each app's `firewall` file) are `route` rules, and those match the
  **container** port after Docker's DNAT: FitTrackee's rule says 5000, not 5001.
  They only started to matter once ufw-docker was installed with
  `--docker-subnets` (see `stacks/README.md`); before that the LAN got through
  regardless.
- **roastery sleeps.** Ollama there is a tray app that only answers while someone is
  logged in, and nothing here wakes roastery before a chat.
- **Rebuild the embedding worker now and then**
  (`./compose.sh embedding-worker build --no-cache`): nothing watches a local
  build's Python dependencies.

## Data

| Path | Contents | Back up |
|---|---|---|
| `/srv/data/n8n` | workflows, credentials (encrypted with `N8N_ENCRYPTION_KEY`) | **yes**, and the key to flask |
| `/srv/data/pourover` | pourOver's SQLite (command log, queue, confirms) | yes (a `.dump`); the tasks are in Vikunja |
| `/srv/data/immich/library`, `immich/postgres` | photos, database | **yes** (database as a dump; thumbnails and encoded video excluded) |
| `/srv/data/immich-ml/model-cache` | model weights | no; downloaded again |
| `/srv/data/opencloud/data`, `opencloud/config` | all file/identity metadata, content, generated config and keys | **yes**, together; restore test required |
| `/srv/data/postgres-vector` | embeddings | no; derived, can be rebuilt |
| `/srv/data/karakeep*`, `openwebui`, `fittrackee`, `postgres-fittrackee`, `traccar`, `esphome` | app data | yes (Postgres as a dump) |
| `/srv/data/speedtest-tracker`, `traefik/acme` | history, certificates | no |

## Known gaps

- **No CrowdSec in front of Immich or OpenCloud.** On percolator, both sat
  behind traefik-ingress with the CrowdSec bouncer; grinder's Traefik has none,
  and both are published through the tunnel behind their own sign-in. Decide
  before the tunnel routes go live (phase 11).

- **Open WebUI can't reach Ollama once roastery binds it to localhost** behind its
  own Traefik and Authelia. That needs machine-to-machine auth that keeps Authelia
  in front; nothing exists yet, and there's no bypass on purpose.
- **Unpinned images:** n8n (`latest`), Open WebUI (`main`), Karakeep (`release`).
- **Karakeep's `NEXTAUTH_URL`** is the direct-port URL while its route is
  `karakeep.${DOMAIN}`. Check the phone's share sheet signs in through the hostname.
- **Never turn on trusted-header SSO in Open WebUI** while `:8081` is published: any
  LAN client could forge the header.
- **Traccar is on H2**, not Postgres; fine for GPS pings, revisit if that changes.
