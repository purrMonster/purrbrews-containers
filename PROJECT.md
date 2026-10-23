---
project: purrbrews-containers
status: active
status_reason: Fleet infrastructure is on main; recovery verification and service rollouts remain open.
resume_trigger: n/a
last_activity: 2026-10-23
last_reviewed: 2026-10-23
repo: https://github.com/purrMonster/purrbrews-containers
related: ["[[persianPerch]]", "[[meowGram]]", "[[purrCafe]]", "[[pourOver]]"]
tags: [project]
---

# PurrBrews containers

## What it is

Infrastructure for the PurrBrews self-hosted fleet: provisioning, service stacks, access, monitoring, backups and recovery.
Five Debian nodes plus Windows workstation roastery; Docker Compose, Bash/PowerShell, Python, Traefik, Authelia/LLDAP, restic and Tailscale.
Application code belongs in separate repos; start with the [map](docs/MAP.md) and [README](README.md).

## Current state

| Area | State | Evidence |
|---|---|---|
| Code | Built on main; meowGram 2.0.0 pinned with bots off. pourOver partial (digest placeholder). | [Reviewed main: 9593317](https://github.com/purrMonster/purrbrews-containers/commit/959331772651c50b27ae7eab8ff4329650ae404b), [pourOver](stacks/grinder/pourover/docker-compose.yml) |
| Release | No repo tags or GitHub releases found on 2026-10-23; deployments use reviewed commits and upstream images. | [Releases](https://github.com/purrMonster/purrbrews-containers/releases), [operations](docs/operations.md) |
| Deployment | Five Linux stacks checked October 13; all six Komodo agents, nine Scrutiny drives, Gatus and percolator's meowGram/purrCafe recorded October 14. Not rechecked live today. | [Fleet](runbook.md#2026-10-13--fresh-fleet-up-all-five-linux-nodes-deployed-and-checked-session-handoff), [agents](runbook.md#2026-10-14--agents-step-done-komodo-pairs-all-six-machines-scrutiny-sees-every-drive-session-handoff), [meowGram](runbook.md#2026-10-14--meowgram-live-on-percolator-bring-up), [purrCafe](https://github.com/purrMonster/purrbrews-containers/commit/e710d4f22d69b0781bded332a48c98c65f6fbb91) |
| Tests / CI | Failing on main October 23: pytest failed, both Windows jobs passed. Local pytest unavailable (module absent). Runbook records pourOver's missing digest failing the pin test. | [CI run](https://github.com/purrMonster/purrbrews-containers/actions/runs/39900104940), [rehearsal](runbook.md#2026-10-23--meowgram-200-r2-bots-built-in-left-off), [workflow](.github/workflows/tests.yml) |

## Open points

- Prove backups after rebuild: roastery repository, sieve's restic password, first nightly per node, isolated OpenCloud/Radicale restores and flask recovery kit. September restore success predates rebuilding. [Handoff](runbook.md#2026-10-14--agents-step-done-komodo-pairs-all-six-machines-scrutiny-sees-every-drive-session-handoff).
- Resolve pourOver's image digest and failing pin test; provision the approved service account, deploy optionally on grinder, then test alerts. No deployment recorded. [Plan](runbook.md#2026-10-21--pourover-joins-grinder-as-an-optional-app).
- meowGram 2.0.0 rollout: stop server, dump and copy database off-node first; schema 6 rollback requires restoring the old dump. Bots stay off. [Procedure](runbook.md#2026-10-23--meowgram-200-r2-bots-built-in-left-off).
- persianPerch: public image verified, credentials and cellar bring-up still open. [Handoff](runbook.md#2026-10-21--persianperch-after-the-ghcr-switch-the-leftovers).
- Finish Cloudflare routes, client sign-ins, DAV isolation/token checks, mail relay and test messages, Open WebUI migration from old Ollama endpoint. [Backlog](runbook.md#backlog--open-items).
- Verify fetch-only timers, deploy records, disk warnings and SSH fingerprints. Drift reporting and first-deploy network creation remain proposals. [Backlog](runbook.md#backlog--open-items).

## Branches

Remote inventory checked 2026-10-23; dates are tip commit dates. Merged leftovers look stale.

- `claude/feline-bot-names` — AGENTS.md: bots get cat-breed names, picked by the owner; 2026-10-13, merged; stale.
- `claude/ha-bluetooth-caps` — homeassistant: add NET_ADMIN, NET_RAW so Bluetooth isn't degraded; 2026-10-13, merged; stale.
- `claude/immich-3.3.3-pair` — immich: server and ML to v3.3.3 together, so the pair test passes; 2026-10-23, unmerged; current.
- `claude/llama-swap-inline-image` — llama-swap: write the image on both services, not as a YAML anchor; 2026-10-23, unmerged; current.
- `claude/mail-relay-clients` — percolator: Paperless, Immich, Vikunja and Mealie send mail through the relay; 2026-10-13, merged; stale.
- `claude/meowgram-2.0.0` — meowgram: 2.0.0, with bots explicitly off and the dump as the rollback; 2026-10-23, merged; stale.
- `claude/meowgram-live` — runbook: meowGram live on percolator; sign-in test and tunnel route still open; 2026-10-14, merged; stale.
- `claude/meowgram-mobile-callback` — Merge branch 'claude/meowgram-on-percolator' into claude/meowgram-mobile-callback; 2026-10-14, merged; stale.
- `claude/meowgram-on-percolator` — Merge pull request #60 from purrMonster/claude/meowgram-mobile-callback; 2026-10-14, old integration tip; superseded per runbook, ancestry unmerged.
- `claude/n8n-healthcheck-ipv4` — n8n: health-check on 127.0.0.1, since localhost is ::1 in the container; 2026-10-13, merged; stale.
- `claude/perch-after-ghcr` — persian-perch: tidy after the GHCR switch; two backlog lines answered; 2026-10-20, merged; stale.
- `claude/purrcafe-deployed` — runbook: purrCafe live on percolator; DNS, Gatus and alert test done, tunnel route open; 2026-10-14, merged; stale.
- `claude/purrcafe-percolator` — runbook: purrCafe joins percolator; deploy and panel steps in the backlog; 2026-10-14, merged; stale.
- `claude/radicale-data-mount` — radicale: mount the data parent so uid PUID can reach /data/collections; 2026-10-13, merged; stale.
- `claude/roastery-deploy-checkout` — runbook: 2026-10-13 handoff, fresh fleet up; today's fixes ticked with evidence; 2026-10-13, merged; stale.
- `claude/roastery-scrutiny-collector` — roastery: Scrutiny's native Windows collector, as a SYSTEM task; 2026-10-14, merged; stale.
- `claude/runbook-2026-10-14-handoff` — runbook: 2026-10-14 handoff, agents step done; Scrutiny lines ticked with evidence; 2026-10-14, merged; stale.
- `claude/runbook-pr43-merged` — runbook: OpenCloud and Radicale reviewed, pushed and merged (#43); 2026-10-13, merged; stale.
- `claude/scrutiny-host-labels` — scrutiny: label each node's drives with its name; 2026-10-14, merged; stale.
- `claude/tunnel-forwarded-headers` — traefik: trust sieve's forwarded headers on mochaPot and grinder too; 2026-10-13, merged; stale.
- `claude/upgrade-gate-records-install` — upgrade-gate: record the installed version so redeploys pass; 2026-10-13, merged; stale.
- `codex/opencloud-radicale` — merge: retain new mail-relay clients alongside the file replacement; 2026-10-13, merged; stale.
- `dependabot/docker_compose/stacks/grinder/fittrackee/docker_compose-16ddfce1ea` — deps: bump fittrackee/fittrackee in /stacks/grinder/fittrackee; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/grinder/karakeep/docker_compose-3defd4c36c` — deps: bump karakeep-app/karakeep in /stacks/grinder/karakeep; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/grinder/n8n/docker_compose-abba6a689d` — deps: bump n8nio/n8n in /stacks/grinder/n8n; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/grinder/openwebui/docker_compose-516aeb8044` — deps: bump open-webui/open-webui in /stacks/grinder/openwebui; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/mochaPot/homeassistant/docker_compose-2d526c9803` — deps: bump home-assistant/home-assistant; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/mochaPot/musicassistant/docker_compose-c2e109097a` — deps: bump music-assistant/server in /stacks/mochaPot/musicassistant; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/percolator/homepage/docker_compose-6a00262c28` — deps: bump gethomepage/homepage in /stacks/percolator/homepage; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/percolator/immich/docker_compose-1c973d9df9` — deps: bump immich-app/immich-server in /stacks/percolator/immich; 2026-10-19, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/percolator/paperless/docker_compose-99074322e7` — deps: bump paperless-ngx/paperless-ngx in /stacks/percolator/paperless; 2026-10-12, unmerged; review whether superseded.
- `dependabot/docker_compose/stacks/percolator/radicale/docker_compose-120a488f39` — deps: bump tomsquest/docker-radicale in /stacks/percolator/radicale; 2026-10-12, unmerged; review whether superseded.
- `dependabot/pip/stacks/grinder/embedding-worker/fastapi-0.143.0` — deps: bump fastapi in /stacks/grinder/embedding-worker; 2026-10-19, unmerged; review whether superseded.
- `docs/project-card` — this card; new review branch.

## Key decisions

- 2026-09-15 · Public repo; secrets generated locally. · [Decision](runbook.md#2026-09-15--public-repository-zero-secrets-in-transit).
- 2026-09-15 · Per-node Traefik, central SSO. · [Decision](runbook.md#2026-09-15--a-traefik-on-every-node-sso-stays-central).
- 2026-09-27 · restic backups, database dumps and separate copies. · [Decision](runbook.md#2026-09-27--backup-design-decided).
- 2026-10-07 · llama-swap replaces Ollama; game mode shares GPU capacity. · [Decision](runbook.md#2026-10-07--roastery-wiped-llama-swap-replaces-ollama-with-a-game-mode).
- 2026-10-12 · Fetch main; explicitly deploy reviewed commits. · [Decision](runbook.md#2026-10-12--reviewed-deployments-nodes-fetch-main-they-dont-pull-it).
- 2026-10-12 · OpenCloud and Radicale replace Nextcloud. · [Decision](runbook.md#2026-10-12--nextcloud-decommissioned-opencloud-and-radicale-replace-it).
- 2026-10-23 · meowGram bots off; pre-upgrade dump is rollback. · [Decision](runbook.md#2026-10-23--meowgram-200-r2-bots-built-in-left-off).

## How to resume

1. Read [AGENTS.md](AGENTS.md), [Backlog](runbook.md#backlog--open-items) and newest entries; check git status, remote main and CI. Preserve others' edits.
2. Check fleet status read-only as barista; reconcile dated evidence, prioritizing backup/restore proof and CI before upgrades.
3. Choose one backlog item; obtain node-change approval with rollback, follow its README and [operations](docs/operations.md), then verify health and affected alerts.

## Decisions to remake

- Docker-group access: older backlog assumes membership; October 14 records barista outside it. Confirm intended privilege policy. [Evidence](runbook.md#2026-10-14--meowgram-live-on-percolator-bring-up).
- Backup recovery: reconcile restoring the old repository versus initializing fresh before trusting new writes. [Backlog](runbook.md#backlog--open-items), [latest handoff](runbook.md#2026-10-14--agents-step-done-komodo-pairs-all-six-machines-scrutiny-sees-every-drive-session-handoff).
- Review DAV brute-force protection before public access and authentication before enabling meowGram bots. [Backlog](runbook.md#backlog--open-items), [bot boundary](runbook.md#2026-10-23--meowgram-200-r2-bots-built-in-left-off).

## Questions for Roastmaster

- Which backup, mail, tunnel, client-login and optional-service steps have finished since their last dated entries?
- Has meowGram 2.0.0 been deployed with its off-node dump, or is percolator still on the earlier version?
- Should the uncommitted `codex/llama-swap-consumption-doc` work be integrated? Its local runbook reports successful CPU chat and Riot launcher exclusion checks on 2026-10-16; those entries and the consumer guide are absent from main and need separate review.
- Are remote LLM Basic authentication, streaming, normal GPU generation and real-game detection now verified? Local October 16 notes leave these open; main's [pourOver plan](runbook.md#2026-10-21--pourover-joins-grinder-as-an-optional-app) specifies the Basic-auth pattern.

## Card history

- 2026-10-23 · Created by Codex from refreshed main, remote CI/branches and explicitly marked local notes. Only PROJECT.md changed; no node changes. Next: owner reviews the project-card PR; existing CI failure and missing local pytest remain.
