# purrBrews map

One page to find everything. Update it whenever a project, doc or node is added.
Decisions and their reasons live in [`runbook.md`](../runbook.md); this page only
points.

_Last updated: 2026-09-26_

## Start here

| Doc | What it's for |
|---|---|
| [`README.md`](../README.md) | What the fleet is, how a node is built, design principles |
| [`runbook.md`](../runbook.md) | Dated decisions (newest first) and the backlog, ticked only on evidence |
| [`docs/network-audit.md`](network-audit.md) | September 2026 fleet audit: DNS/IPv6 findings and rollout |
| [`stacks/README.md`](../stacks/README.md) | Conventions shared by every node's stacks |

## Nodes

| Node | IP | Role | README |
|---|---|---|---|
| sieve | .10 | Network: Pi-hole, Unbound, cloudflared, ntfy, Gatus, NetAlertX | [stacks/sieve](../stacks/sieve/README.md) |
| percolator | .11 | Ingress + identity (Traefik, Authelia, LLDAP) and daily apps | [stacks/percolator](../stacks/percolator/README.md) |
| cellar | .12 | Backups (restic), shares, Scrutiny hub, Komodo | [stacks/cellar](../stacks/cellar/README.md) |
| mochaPot | .13 | Home Assistant, Music Assistant, secondary Pi-hole, kiosk | [stacks/mochaPot](../stacks/mochaPot/README.md) |
| grinder | .14 | Automation + AI indexing (n8n, pgvector, embeddings, Open WebUI, Karakeep) | [stacks/grinder](../stacks/grinder/README.md) |
| roastery | — | Windows workstation: bootstrap server, Ollama (3080), Immich ML | [stacks/roastery/traefik](../stacks/roastery/traefik/README.md) |

## Projects

| Project | Status | Plan | Runbook entry |
|---|---|---|---|
| Fleet rebuild (purrbrews-containers) | Stacks running; backups unfinished | [README](../README.md) | 2026-09-15 → 2026-09-16 entries |
| Backups (restic sources, DB dumps, restore test) | Open | [cellar README § restic](../stacks/cellar/README.md#restic) | Backlog |
| **Second brain** | **Planned 2026-09-26, Phase 0 (questions open)** | [docs/second-brain/design-plan.md](second-brain/design-plan.md) | 2026-09-26 — Second brain: design plan |
| Smart desk / smart mirror | Idea | — | — |

## Where data lives (quick reference)

| Kind of thing | App | Node |
|---|---|---|
| Notes (planned) | Obsidian vaults via Syncthing | devices + grinder + cellar |
| Links / read-later | Karakeep | grinder |
| Documents | Paperless-ngx | percolator |
| Photos, screenshots | Immich | percolator |
| Files, calendars, contacts | Nextcloud | percolator |
| Tasks | Vikunja | percolator |
| Passwords | Vaultwarden | percolator |
| Recipes | Mealie | percolator |
| Budget | Actual Budget | percolator |
