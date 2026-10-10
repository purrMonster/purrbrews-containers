# purrBrews map

One page to find everything. Update it whenever a project, doc or node is added.
Decisions and their reasons live in [`runbook.md`](../runbook.md); this page only
points.

_Last updated: 2026-10-10_

## Start here

| Doc | What it's for |
|---|---|
| [`README.md`](../README.md) | What the fleet is, how a node is built, design principles |
| [`AGENTS.md`](../AGENTS.md) | Rules for every AI agent working here: scope, git, evidence, nodes, handoff |
| [`docs/operations.md`](operations.md) | Reviewed releases, deployment phases, recovery, secrets and readiness targets |
| [`docs/image-upgrades.md`](image-upgrades.md) | Locked image versions, migration gates and rollout checks |
| [`runbook.md`](../runbook.md) | Dated decisions (newest first) and the backlog, ticked only on evidence |
| [`docs/network-audit.md`](network-audit.md) | September 2026 fleet audit: DNS/IPv6 findings and rollout |
| [`stacks/README.md`](../stacks/README.md) | How every node's stacks work, and how to add an app or a node |
| [`tailscale/README.md`](../tailscale/README.md) | Remote access: SSH to the nodes and RDP to roastery over the tailnet |
| [`docs/flask.md`](flask.md) | flask, the offline recovery kit: what's on it, which secrets, how it's kept |
| [`docs/cleanup-review.md`](cleanup-review.md) | Cleanup evidence, intentionally retained components and follow-ups |
| [`Deprecated/README.md`](../Deprecated/README.md) | Archive index and restoration convention |
| [`stacks/_shared/README.md`](../stacks/_shared/README.md) | Shared Linux Compose definitions and node-specific overrides |

## Nodes

| Node | IP | Role | README |
|---|---|---|---|
| sieve | .10 | Network: Pi-hole, Unbound, cloudflared, ntfy, Gatus, NetAlertX | [stacks/sieve](../stacks/sieve/README.md) |
| percolator | .11 | Ingress + identity (Traefik, Authelia, LLDAP) and daily apps | [stacks/percolator](../stacks/percolator/README.md) |
| cellar | .12 | Backups (restic), shares, Scrutiny hub, Komodo | [stacks/cellar](../stacks/cellar/README.md) |
| mochaPot | .13 | Home Assistant, Music Assistant, secondary Pi-hole, kiosk | [stacks/mochaPot](../stacks/mochaPot/README.md) |
| grinder | .14 | Automation + AI indexing (n8n, pgvector, embeddings, Open WebUI, Karakeep) | [stacks/grinder](../stacks/grinder/README.md) |
| roastery | — | Windows workstation: bootstrap server, llama-swap (local LLMs, 3080) with game mode, Immich ML | [stacks/roastery](../stacks/roastery/README.md) |

## Projects

| Project | Status | Plan | Runbook entry |
|---|---|---|---|
| Fleet rebuild (purrbrews-containers) | Linux stacks recorded running; roastery rebuild open after the 2026-10-07 wipe | [README](../README.md) | Backlog and newest entries |
| One toolkit for every node (`stacks/_lib`, `node.conf`) | Done; rolling out node by node | [stacks/README.md](../stacks/README.md) | 2026-09-26 — One toolkit for every node |
| Backups (restic sources, DB dumps, restore test) | Restore tests passed 2026-09-29; clean night recorded 2026-09-30. Restore roastery's repository after its 2026-10-07 wipe | [cellar/restic](../stacks/cellar/restic/README.md) | Backlog and 2026-10-07 entry |
| Remote access (Tailscale on every machine, SSH + RDP) | Done; checked from outside the house 2026-09-28 | [tailscale](../tailscale/README.md) | 2026-09-27 — Remote access over Tailscale |
| flask (offline recovery kit: two bootable USB sticks + paper) | Stick A built and verified 2026-09-29; vault, B and paper next | [docs/flask.md](flask.md) | 2026-09-28 — flask, the recovery kit |
| Local LLMs on roastery (llama-swap replaces Ollama; game mode) | Implementation present; deployment after the wipe remains unverified here | [llama-swap](../stacks/roastery/llama-swap/README.md), [game mode](../stacks/roastery/game-mode/README.md) | 2026-10-07 — roastery wiped; llama-swap replaces Ollama |
| Smart desk / smart mirror | Idea | — | — |

## Where data lives (quick reference)

| Kind of thing | App | Node |
|---|---|---|
| Links / read-later | Karakeep | grinder |
| Documents | Paperless-ngx | percolator |
| Photos, screenshots | Immich | percolator |
| Files, calendars, contacts | Nextcloud | percolator |
| Tasks | Vikunja | percolator |
| Passwords | Vaultwarden | percolator |
| Recipes | Mealie | percolator |
| Budget | Actual Budget | percolator |
| Chat | meowGram (own repo) | roastery, for now |
