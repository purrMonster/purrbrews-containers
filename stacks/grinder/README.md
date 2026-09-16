# grinder

Automation, AI indexing, and shed-able services — 192.168.0.14, HP Pavilion
board (bare board from the Pavilion x360's spare parts, i5 7th gen,
16 GB RAM, 512 GB NVMe). See `infrastructure.md` §2-3.

**grinder is entirely new to this fleet.** It did not exist in the
pre-restructure `purrBrews-infra` repo at all — `infrastructure.md` §1
lists it plainly: "grinder new." Nothing below is a migration; it's a
from-scratch build, though a couple of compose files were adapted from
apps that existed elsewhere pre-restructure (n8n, Speedtest Tracker) where
the shape was worth reusing.

**grinder runs nine things**, per `infrastructure.md` §4, plus its own
Traefik added 2026-09-16 so every web-facing app gets real HTTPS on a
pretty hostname instead of bare LAN IP:port:

| App | What it does |
|---|---|
| [n8n](#n8n) | Workflow automation — orchestrates the rest |
| [postgres-vector](#postgres-vector) | Postgres + pgvector — the second brain's vector store |
| [embedding-worker](#embedding-worker) | CPU embedding API — custom-built, no off-the-shelf image exists |
| [openwebui](#openwebui) | Chat UI for roastery's wake-on-demand Ollama |
| [karakeep](#karakeep) | Bookmark/read-it-later manager |
| [fittrackee](#fittrackee) | Self-hosted activity tracker (bike computer pipeline) |
| [traccar](#traccar) | Live position tracking (bike computer pipeline) |
| [esphome](#esphome) | ESP32 sensor fleet management |
| [speedtest-tracker](#speedtest-tracker) | Periodic ISP speed tests |
| [traefik](#traefik) | Reverse proxy + real TLS, with a native-login backdoor |

## Why grinder, specifically

`infrastructure.md` §4: "`grinder` holds nothing household-critical.
Everything on it is cheap to shed, which is what makes its free memory the
landing zone when another node dies." Every app on this list is useful but
not load-bearing for anyone else's day — if grinder is down for an
evening, nobody notices except whoever's mid-bike-ride or mid-chat with a
local model.

This is also the "second brain" and edge/sensors node from
`edge-and-automation.md`: `n8n` orchestrates ingestion and classification
pipelines, `postgres-vector` + `embedding-worker` are the "Index" step
("embeddings + pgvector on CPU, always on. Only synthesis needs the
3080, via WoL"), and `esphome`/`traccar`/`fittrackee` are the sensor and
bike-computer endpoints that same document plans out in detail.

## Traefik and the native-login backdoor

grinder now runs its own Traefik, fronting every app with a web UI:
`n8n.${DOMAIN}`, `chat.${DOMAIN}` (Open WebUI), `karakeep.${DOMAIN}`,
`fittrackee.${DOMAIN}`, `traccar.${DOMAIN}`, `esphome.${DOMAIN}`,
`speedtest.${DOMAIN}`. `postgres-vector` and `embedding-worker` have no
web UI and aren't fronted — they're only ever reached over `grinder_net`
by container name.

Every fronted app keeps its own direct host port published too — the
deliberate backdoor. Unlike cellar's Scrutiny or mochaPot's Music
Assistant (which have no login at all), every app on grinder already has
a real native account of its own, so the backdoor here is never a
zero-auth fallback: it's n8n's owner account, Open WebUI's own auth,
Karakeep's NextAuth login, FitTrackee's account, Traccar's admin login
(change the default immediately — see its own section below), ESPHome's
basic auth, or Speedtest Tracker's admin login, all reachable directly at
`http://${GRINDER_LAN_IP}:<port>` with no Traefik or Authelia in the
path, whenever percolator's Authelia (or Traefik itself) is down.

## First-time setup on grinder

```sh
cd /opt/purrbrews/stacks/grinder
./setup-secrets.sh
```

Creates `.env.local`, prompts for `REPLACE_ME` (LAN IP, domain, roastery's
LAN IP, LAN interface name), runs `generate-secrets.sh`, then
`render-configs.sh`. Re-run any time; every step is idempotent.

Suggested order: **postgres-vector** first (embedding-worker and any n8n
workflow that uses it depend on it existing), then **embedding-worker**,
then the rest in any order.

## Bringing each app up

### n8n

```sh
sudo mkdir -p /srv/data/n8n
./compose.sh n8n up -d
```

Owner account on first visit to `http://${GRINDER_LAN_IP}:5678`, no
default credentials. SQLite for n8n's own state — the second-brain
pipeline's actual data lives in `postgres-vector`, reached from n8n's HTTP
Request nodes and Postgres nodes by container name
(`postgres-vector:5432`) once both are on `grinder_net`.

### postgres-vector

```sh
sudo mkdir -p /srv/data/postgres-vector
./compose.sh postgres-vector up -d
```

`CREATE EXTENSION vector` runs automatically on first boot via
`init-pgvector.sql`. No ports published — reached only by `n8n` and
`embedding-worker`, by container name.

### embedding-worker

```sh
./compose.sh embedding-worker up -d --build
curl http://${GRINDER_LAN_IP}:8000/health   # will fail -- not published, see below
docker exec -it embedding-worker curl localhost:8000/health   # this works
```

Custom-built (`Dockerfile` in this app's own directory) — no off-the-shelf
image exists for "the specific embedding model this project wants," so
this is a small FastAPI wrapper around `sentence-transformers`, built
locally rather than pulled. Not reachable from the LAN at all, only from
`n8n` over `grinder_net` (`http://embedding-worker:8000/embed`, POST
`{"texts": [...]}`, gets back normalized vectors). See the compose file's
own comment on why this means Diun can't track its freshness the normal
way — rebuild by hand periodically.

### openwebui

```sh
sudo mkdir -p /srv/data/openwebui
./compose.sh openwebui up -d
```

First account at `http://${GRINDER_LAN_IP}:8081` becomes admin. **roastery
has to already be awake, logged in, with the Ollama tray app running** for
chat requests to actually work — `infrastructure.md` §9 is explicit that
Ollama on Windows is a per-user tray app, not a background service, and
starts at login, not at boot. See "Known gaps" below — this stack doesn't
yet automate waking roastery for a chat request.

### karakeep

```sh
sudo mkdir -p /srv/data/karakeep /srv/data/karakeep-meilisearch
./compose.sh karakeep up -d
```

First visit to `http://${GRINDER_LAN_IP}:3030` — flip
`DISABLE_SIGNUPS` to `false` in `docker-compose.yml` for that one account
creation, then back to `true` and restart, same discipline as every other
app in this fleet with its own user accounts.

### fittrackee

```sh
sudo mkdir -p /srv/data/fittrackee/uploads /srv/data/postgres-fittrackee
./compose.sh fittrackee up -d
```

First account at `http://${GRINDER_LAN_IP}:5001` — confirm against the
image's own current docs whether it becomes admin automatically; not
verified against a real bring-up as of this rebuild. Feeds from
`edge-and-automation.md` §5's pipeline: OpenTracks/OsmAnd GPX on the
Pixel 6a → Nextcloud → n8n watches the folder → pushes to this API.

### traccar

```sh
sudo mkdir -p /srv/data/traccar/data /srv/data/traccar/logs
./compose.sh traccar up -d
```

**Log in immediately at `http://${GRINDER_LAN_IP}:8082` with
`admin`/`admin` and change it** — this image's default credential isn't
settable via compose/env, it's a first-login manual step. Traccar Client
on the Pixel 6a posts to `http://${GRINDER_LAN_IP}:5055`.

### esphome

```sh
sudo mkdir -p /srv/data/esphome
./compose.sh esphome up -d
```

Dashboard at `http://${GRINDER_LAN_IP}:6052`, login `barista` / the
password `generate-secrets.sh` created. **Set up the dedicated 2.4 GHz
WPA2 SSID before flashing the first ESP32** (`edge-and-automation.md`
§6a) — band steering and WPA3/mixed mode both break ESP32 association,
intermittently, which is worse than a clean failure.

### speedtest-tracker

```sh
sudo mkdir -p /srv/data/speedtest-tracker/config
./compose.sh speedtest-tracker up -d
```

Dashboard at `http://${GRINDER_LAN_IP}:8765`. **Confirm `docker logs
speedtest-tracker` actually shows a scheduled run happening** — this
app's most common real-world failure mode is silently never running a
test at all if `SPEEDTEST_SCHEDULE` isn't picked up, no error surfaced.

### traefik

```sh
sudo mkdir -p /srv/data/traefik/acme
./compose.sh traefik up -d
docker logs traefik --tail 50   # look for a successful cert issuance
```

Needs `traefik/secrets.env.local`'s `CF_DNS_API_TOKEN` and
`TRAEFIK_ACME_EMAIL` in `.env.local`. Add Local DNS Records in sieve's
Pi-hole (once sieve exists in this repo) for each `*.${DOMAIN}` hostname
listed above, pointing at `${GRINDER_LAN_IP}`. Until then, or until
percolator's Authelia exists, use each app's direct port — see "Traefik
and the native-login backdoor" above.

## What's here now

- `compose.sh` — wrapper so every app's `docker-compose.yml` sees the
  shared `.env.local` plus its own `secrets.env.local`, and ensures
  `grinder_net` exists.
- `render-configs.sh` — renders `*.template` files. Copied verbatim.
- `setup-secrets.sh` — first-time-setup script.
- `generate-secrets.sh` — generates every app's secrets except openwebui
  (its own onboarding UI), embedding-worker (no auth surface) and traccar
  (first-login manual change).
- `local.env.example` — copy to `.env.local` and fill in:
  `GRINDER_LAN_IP`, `TZ`, `DOMAIN`, `ROASTERY_LAN_IP`,
  `GRINDER_LAN_INTERFACE`, `PERCOLATOR_LAN_IP`, `TRAEFIK_ACME_EMAIL`.
- `.gitignore` — same rules as every other node's.
- One directory per app, each with its own `docker-compose.yml` (or, for
  `embedding-worker`, a `Dockerfile` + `requirements.txt` + `app.py` it
  builds from). Every app with a web UI carries Traefik labels.
- `traefik/` — reverse proxy + real TLS, with the ForwardAuth middleware
  definition in `config/dynamic.yml.template`. See "Traefik and the
  native-login backdoor" above.

## Known gaps / things to double-check before relying on this

- **Traefik's ForwardAuth route won't actually work yet.** It depends on
  percolator's Authelia, which now exists in this repo, but grinder isn't
  registered with it yet — its IP still needs adding to percolator's
  `FORWARD_AUTH_CLIENTS`/`firewall.sh` and to Authelia's admin-host list
  (tracked in `runbook.md`'s backlog). Until then, every `*.${DOMAIN}`
  hostname on this node will 502/504 through Traefik. The direct-port
  backdoor (see "Traefik and the native-login backdoor" above) is what
  actually works today.
- **No local DNS records exist yet** for any of grinder's `*.${DOMAIN}`
  hostnames — until sieve's Pi-hole has them, reach an app by
  `https://${GRINDER_LAN_IP}` with a cert-mismatch warning (expected), or
  use its direct port.
- **No automated wake for roastery.** Open WebUI needs Ollama already
  running on roastery; nothing here sends the WoL packet automatically
  before a chat request. `cellar/restic/mirror-to-roastery.sh` has a
  working WoL-then-wait pattern that could be adapted into an n8n workflow
  or a small script here — not done yet.
- **embedding-worker is genuinely new code, not a reused/audited image.**
  `BAAI/bge-small-en-v1.5` was chosen for being small enough to run
  comfortably on this node's CPU, not benchmarked against alternatives.
  Revisit if retrieval quality in practice turns out to matter more than
  this default assumed.
- **Traccar uses its bundled H2 database, not Postgres**, unlike
  FitTrackee — a deliberate call (see the compose file's own comment),
  worth revisiting if Traccar's data volume or a need for concurrent
  access changes that trade-off.
- **No Komodo Periphery agent yet.** Same as mochaPot — add one from
  `stacks/_templates/komodo-periphery/` (once migrated into this repo)
  when fleet-wide management of grinder's containers is actually wanted.
- **No Scrutiny collector yet**, despite grinder having its own NVMe worth
  monitoring — add `scrutiny-collector/` pointed at cellar's hub (see
  `stacks/cellar/README.md`) when that's worth doing.
- **Nothing here is tested against real hardware yet.** grinder is new to
  this fleet as of this rebuild — every bring-up step above is
  best-understanding-at-write-time, not confirmed against a live node.
