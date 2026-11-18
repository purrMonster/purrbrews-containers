# purrBrews map

One page to find everything. Update it whenever a doc, a stack group or a node
is added. Decisions and their reasons live in [`runbook.md`](../runbook.md);
this page only points.

_Last updated: 2026-11-16 (the rebuild after the move)_

## Start here

| Doc | What it's for |
|---|---|
| [`README.md`](../README.md) | What the fleet is and how the repo is laid out |
| [`AGENTS.md`](../AGENTS.md) | Rules for every AI agent working here: scope, git, evidence, nodes, handoff |
| [`runbook.md`](../runbook.md) | Decisions since 2026-11-16 and the Backlog, ticked only on evidence |
| [`docs/migration-plan.md`](migration-plan.md) | The rebuild, phase by phase, and what still has to be written |
| [`docs/hardware.md`](hardware.md) | Which machine is which node, memory and disks, where roastery's jobs went |
| [`payload/README.md`](../payload/README.md) | The bootstrap payload: what makes a fresh machine a node, and how americano serves it |
| [`docs/voice.md`](voice.md) | Voice in each room: Whisper, Piper and a satellite on each ThinkCentre, and how a room is brought up |
| [`docs/recovery-kit.md`](recovery-kit.md) | flask, the offline recovery kit: what's on the sticks and in the vault, and how americano builds it (`recovery/`) |
| [`recovery/RECOVERY.md`](../recovery/RECOVERY.md) | What to do when something is gone: one node, cellar, or everything online |
| [`docs/carry-over-map.md`](carry-over-map.md) | Where every app and file of the old layout went |
| [`stacks/README.md`](../stacks/README.md) | How the stacks and the shared scripts work; adding an app or a node; backups; updates |
| [`docs/operations.md`](operations.md) | Deploying a reviewed commit (`scripts/fleet.py`), recovery targets |
| [`docs/image-upgrades.md`](image-upgrades.md) | Tag-and-digest pins, paired images, upgrades held until acknowledged |
| [`docs/image-updates-2026-11.md`](image-updates-2026-11.md) | The November 2026 image updates: breaking changes acted on, and what's new in each app |
| [`tailscale/README.md`](../tailscale/README.md) | Remote access over the tailnet (written for the old fleet; the join step is in the plan, phase 10) |
| [`deprecated/ABOUT.md`](../deprecated/ABOUT.md) | The archive: the old runbook, README, bootstrap, init and roastery |

## Nodes

| Node | Address | Role | Folder |
|---|---|---|---|
| sieve | .10 | Network: Pi-hole, Unbound, cloudflared, ntfy, Gatus, NetAlertX | [nodes/sieve](../nodes/sieve/README.md) |
| percolator | .11 | Ingress and identity (Traefik, Authelia, LLDAP) and the household apps | [nodes/percolator](../nodes/percolator/README.md) |
| cellar | .12 | Backup hub and repository, Scrutiny hub, Komodo | [nodes/cellar](../nodes/cellar/README.md) |
| mochaPot | .13 | Home Assistant, Music Assistant, secondary Pi-hole, kiosk | [nodes/mochaPot](../nodes/mochaPot/README.md) |
| grinder | .14 | Automation and AI: n8n, pgvector, LiteLLM, Open WebUI, Immich ML, self-tracking | [nodes/grinder](../nodes/grinder/README.md) |

## Stack groups

| Group | What's in it |
|---|---|
| [`network`](../stacks/network) | DNS, DHCP, the tunnel, the three Traefiks, CrowdSec, NetAlertX |
| [`identity`](../stacks/identity) | LLDAP, Authelia |
| [`mail`](../stacks/mail) | The relay to Purelymail |
| [`apps`](../stacks/apps) | What the household opens: passwords, files, calendars, photos, documents, recipes, tasks, budget, chat, feeds, bookmarks, tracking |
| [`home`](../stacks/home) | Home Assistant, Music Assistant, ESPHome, the kiosk |
| [`automation`](../stacks/automation) | n8n, pgvector, the embedding worker, pourOver |
| [`ai`](../stacks/ai) | LiteLLM, Open WebUI, Immich's machine learning |
| [`monitoring`](../stacks/monitoring) | Gatus, ntfy, Speedtest Tracker |
| [`fleet-management`](../stacks/fleet-management) | Komodo and its agent, Scrutiny and its collector, persianPerch |
| [`backup`](../stacks/backup) | restic (the hub and every node's settings), Samba, NFS |

## Where data lives (quick reference)

| Kind of thing | App | Node |
|---|---|---|
| Passwords | Vaultwarden | percolator |
| Files | OpenCloud | percolator |
| Calendars, contacts | Radicale | percolator |
| Photos | Immich | percolator |
| Documents | Paperless-ngx | percolator |
| Tasks | Vikunja | percolator |
| Recipes | Mealie | percolator |
| Budget | Actual Budget | percolator |
| Chat | meowGram (own repo) | percolator |
| Household dashboard | purrCafe (own repo) | percolator |
| Links, read-later | Karakeep | grinder |
| Automations and their vectors | n8n, pgvector | grinder |
| Home automation | Home Assistant | mochaPot |
| Backups | restic repository, database dumps | cellar, with copies on Google Drive and two offline disks (planned) |

## Related repositories

| Repo | What it is |
|---|---|
| purrbrews-bootstrap | Turns a fresh Debian install into a node and keeps its SSH keys in step |
| persianPerch, pourOver, meowGram, purrCafe | Apps with their own repos; this repo only runs their published images |
