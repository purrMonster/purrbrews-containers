# grinder

**Automation, AI indexing and the self-tracking apps**: `192.168.0.14`, a bare HP
Pavilion board (i5 7th gen, 16 GB, 512 GB NVMe).

Nothing on grinder is household-critical, on purpose. If it's down for an evening
nobody notices, which is also what makes its spare memory the landing zone when
another node dies.

| App | URL | What it's for |
|---|---|---|
| n8n | `n8n.${DOMAIN}`, or `:5678` | Workflow automation; ties the rest together |
| postgres-vector | — | Postgres + pgvector, the vector store |
| embedding-worker | — | CPU embeddings for n8n, built here (`embedding-worker/Dockerfile`) |
| Open WebUI | `chat.${DOMAIN}`, or `:8081` | Chat with the models on roastery's GPU |
| Karakeep | `karakeep.${DOMAIN}`, or `:3030` | Bookmarks and read-it-later |
| FitTrackee | `fittrackee.${DOMAIN}`, or `:5001` | Rides, from the bike computer's GPX |
| Traccar | `traccar.${DOMAIN}`, or `:8082` (phone posts to `:5055`) | Live position of the bike |
| ESPHome | `esphome.${DOMAIN}`, or `:6052` | The ESP32 sensors |
| Speedtest Tracker | `speedtest.${DOMAIN}`, or `:8765` | Hourly ISP speed tests |
| Traefik | — | HTTPS for all of the above, behind Authelia |
| Komodo Periphery | — | Lets Komodo on cellar manage this node's containers |
| Scrutiny collector | — | SMART data for the hub on cellar |

Every app with a UI is behind Authelia on its hostname and keeps its own port open
to the LAN. Unlike on cellar or mochaPot, every one of those ports has a real login
of its own, so the way in when Authelia is down is never an open door.
postgres-vector and the embedding worker aren't published at all; they're only on
`grinder_net`.

## Setup

As `barista` in `/opt/purrbrews/stacks/grinder`, after `init/purrbrews-init.sh grinder`:

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
| `/srv/data/postgres-vector` | embeddings | no; derived, can be rebuilt |
| `/srv/data/karakeep*`, `openwebui`, `fittrackee`, `postgres-fittrackee`, `traccar`, `esphome` | app data | yes (Postgres as a dump) |
| `/srv/data/speedtest-tracker`, `traefik/acme` | history, certificates | no |

## Known gaps

- **Open WebUI can't reach Ollama once roastery binds it to localhost** behind its
  own Traefik and Authelia. That needs machine-to-machine auth that keeps Authelia
  in front; nothing exists yet, and there's no bypass on purpose.
- **Unpinned images:** n8n (`latest`), Open WebUI (`main`), Karakeep (`release`).
- **Karakeep's `NEXTAUTH_URL`** is the direct-port URL while its route is
  `karakeep.${DOMAIN}`. Check the phone's share sheet signs in through the hostname.
- **Never turn on trusted-header SSO in Open WebUI** while `:8081` is published: any
  LAN client could forge the header.
- **Traccar is on H2**, not Postgres; fine for GPS pings, revisit if that changes.
