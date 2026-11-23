# grinder

> **Carried over from the pre-move fleet (2026-11-16).** This page was written for
> the old layout and hardware. Paths and addresses were updated mechanically; the
> bring-up notes are still the best record of how this node's apps fit together,
> but check each step against [`docs/migration-plan.md`](../../docs/migration-plan.md)
> and [`docs/hardware.md`](../../docs/hardware.md) before relying on it.

**The household's growing data, automation and AI**: `192.168.1.14`, an HP
Pavilion x360 (i5-7200U, 16 GB, one 1 TB WD SN530 NVMe, USB Ethernet; checked
2026-11-23).

On 2026-11-23 (owner) Immich, OpenCloud and Paperless moved here from
percolator, onto the 1 TB disk (Immich next to its machine learning), and the
self-tracking and house apps left: Karakeep, FitTrackee and Traccar to
percolator, ESPHome to cellar, Speedtest Tracker to sieve. The three
household apps are what goes down with grinder: photo backup, file sync and
documents wait. Automation and AI can be down for an evening without anyone
noticing. All three still sign in through Authelia on percolator, and send
mail through its relay.

| App | URL | What it's for |
|---|---|---|
| n8n | `n8n.${DOMAIN}`, or `:5678` | Workflow automation; ties the rest together |
| postgres-vector | — | Postgres + pgvector, the vector store |
| embedding-worker | — | CPU embeddings for n8n, built here (`embedding-worker/Dockerfile`) |
| [Immich](../../stacks/apps/immich/) | `immich.${DOMAIN}` (no direct port) | Photos and videos; its own login and Authelia OIDC |
| [Immich ML](../../stacks/ai/immich-ml/) | — (only on `proxy`) | Faces and smart search for Immich, on the CPU |
| [OpenCloud](../../stacks/apps/opencloud/) | `opencloud.${DOMAIN}` (no direct port) | Files, through Authelia OIDC |
| [Paperless-ngx](../../stacks/apps/paperless/) | `paperless.${DOMAIN}` (no direct port) | Scanned documents; Authelia OIDC and a local admin |
| Open WebUI | `chat.${DOMAIN}`, or `:8081` | Chat with the cloud model through LiteLLM |
| [pourOver](../../stacks/automation/pourover/README.md) | none; `:8790` for Gatus only (optional app) | Text in meowGram, a well-filed task in Vikunja |
| Traefik | — | HTTPS for all of the above, behind Authelia |
| Komodo Periphery | — | Lets Komodo on cellar manage this node's containers |
| Scrutiny collector | — | SMART data for the hub on cellar |

n8n and Open WebUI are behind Authelia on their hostnames and keep their own
ports open to the LAN, each with a real login of its own, so the way in when
Authelia is down is never an open door. Immich, OpenCloud and Paperless have
no direct port, only their routes, and their own sign-in (OIDC) instead of
ForwardAuth. postgres-vector, the embedding worker and Immich ML aren't
published at all; they're only on `proxy`.

## Setup

As `barista` in `/opt/purrbrews/nodes/grinder`, once the node is set up (`docs/migration-plan.md`, phase 1):

```bash
./setup-secrets.sh      # asks for DOMAIN, TRAEFIK_ACME_EMAIL, the disk and the
                        # Cloudflare token; generates the rest
sudo ./firewall.sh
# Once, after the relay has run on percolator: its public CA, for Immich's and
# Paperless's mail (stacks/mail/mail-relay/README.md, "Another node's app").
sudo install -d /srv/data/mail-relay/tls-public
scp barista@192.168.1.11:/srv/data/mail-relay/tls-public/ca.crt /tmp/ca.crt
sudo install -m 0644 /tmp/ca.crt /srv/data/mail-relay/tls-public/ca.crt
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
| Immich, OpenCloud, Paperless | Each README's *First run*: sign in through Authelia; Immich's first account is its admin. |
| embedding-worker | `sudo docker exec embedding-worker curl -s localhost:8000/health` |

## Things worth knowing

- **Backdoor ports and the firewall.** These ports are published by Docker, so the
  UFW rules (each app's `firewall` file) are `route` rules, and those match the
  **container** port after Docker's DNAT: Open WebUI's rule says 8080, not 8081.
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
| `/srv/data/paperless/{data,media,export}`, `paperless/postgres` | documents, database | **yes** (database as a dump) |
| `/srv/data/postgres-vector` | embeddings | no; derived, can be rebuilt |
| `/srv/data/openwebui` | chats, settings | yes |
| `/srv/data/mail-relay/tls-public` | the copied relay CA and the bundle built from it | no; copy again |
| `/srv/data/traefik/acme` | certificates | no |

## Known gaps

- **No CrowdSec in front of Immich, OpenCloud or Paperless.** On percolator,
  they sat behind traefik-ingress with the CrowdSec bouncer; grinder's Traefik
  has none, and all three are published through the tunnel behind their own
  sign-in. Decide before the tunnel routes go live (phase 11).
- **Open WebUI can't reach Ollama once roastery binds it to localhost** behind its
  own Traefik and Authelia. That needs machine-to-machine auth that keeps Authelia
  in front; nothing exists yet, and there's no bypass on purpose.
- **Unpinned images:** n8n (`latest`), Open WebUI (`main`).
- **Never turn on trusted-header SSO in Open WebUI** while `:8081` is published: any
  LAN client could forge the header.
