---
project: purrbrews-containers
status: active
status_reason: Fleet rebuilt 2026-10-12/13 and running; backups, mail relay, tunnel routes and new apps still being brought up
status_reason: Fleet infrastructure is on main; recovery verification and service rollouts remain open.
resume_trigger: n/a
last_activity: 2026-10-23
last_reviewed: 2026-10-23
repo: https://github.com/purrMonster/purrbrews-containers
related: ["[[caliCortado]]", "[[persianPerch]]", "[[tabbyTally]]", "[[meowGram]]", "[[purrCafe]]", "[[pourOver]]"]
tags: [project]
---

# purrBrews fleet (purrbrews-containers)

## What it is
Infrastructure as code for the purrBrews home lab: how a bare Debian machine becomes a
fleet node (bootstrap + `init/`), and the Docker Compose stacks each node runs (DNS, SSO,
photos, files, passwords, home automation, AI indexing). Five Debian nodes plus the
Windows workstation roastery. Stack: Debian 13, Docker Compose, Traefik, Authelia + LLDAP,
restic, Python/Bash/PowerShell tooling, pytest in GitHub Actions. Index: [docs/MAP.md](docs/MAP.md).

## Current state
| Area | State | Evidence |
|---|---|---|
| Code | built: every node's stacks, init, `scripts/fleet.py` deploy runner | [stacks/](stacks/), [docs/operations.md](docs/operations.md), `main` at [9593317](https://github.com/purrMonster/purrbrews-containers/commit/9593317) |
| Release | none: no tags or releases; deploys are reviewed `main` commits; images pinned by tag + digest | [docs/image-upgrades.md](docs/image-upgrades.md) |
| Deployment | all five Linux nodes running fresh stacks since 2026-10-13; agents step (Komodo, Scrutiny) done 2026-10-14, nodes at `0c21d76` or later (owner). Not deployed: meowGram 2.0.0, pourOver, mail relay, persianPerch | [runbook.md](runbook.md): 2026-10-13 "Fresh fleet up", 2026-10-14 "Agents step done" |
| Tests / CI | failing: 1 test on `main` since #76 (pourOver's placeholder digest, `test_images_are_pinned`); 112 others pass | Actions run on 9593317, 2026-10-23; runbook 2026-10-23 entry |

## Open points
1. CI red on `main`: pourOver's compose has `sha256:REPLACE_WITH_THE_RELEASE_DIGEST` until pourOver #7 is merged and `v0.1.0` published (runbook 2026-10-21).
2. Backups after the reinstall: fresh repository on roastery, sieve's restic password, first nightly per node, restore test incl. OpenCloud rehearsal (runbook 2026-10-14 "Where we stopped").
3. meowGram 2.0.0 rollout on percolator: dump first, it is the only rollback (Backlog, 2026-10-23 entry).
4. persianPerch bring-up on cellar: `sphynx` in LLDAP, Komodo key, ntfy user, healthchecks.io check (runbook 2026-10-15).
5. Cloudflare tunnel routes in one pass (opencloud, radicale, cafe, meow); then the tunnel client-IP check (Backlog).
6. Fleet mail: Purelymail app password, then the relay; Paperless and Vikunja won't start after a recreate until it has run (Backlog, 2026-10-08 entry).
7. Open PRs: #78 Immich 3.3.3 pair, #79 llama-swap pin, Dependabot #45, #46, #66–#74.
8. sieve and cellar have no `fleet.py` deploy record; percolator needs `OPENCLOUD_UPGRADE_READY=7` before its next deploy (Backlog).
9. Fetch-only timer not yet installed on the nodes (Backlog, 2026-10-12 entry).
10. Docs drift: [docs/MAP.md](docs/MAP.md) last updated 2026-10-14 and [README.md](README.md) still says every node backs up nightly; both predate or ignore the rebuild state.

## Branches
- `claude/immich-3.3.3-pair`: PR #78, open, 1 commit ahead (2026-10-23).
- `claude/llama-swap-inline-image`: PR #79, open, 1 commit ahead (2026-10-23).
- `claude/meowgram-on-percolator`: only a merge commit beyond `main`; PR #59 merged. Stale.
- `claude/feline-bot-names`, `ha-bluetooth-caps`, `mail-relay-clients`, `meowgram-2.0.0`, `meowgram-live`, `meowgram-mobile-callback`, `n8n-healthcheck-ipv4`, `perch-after-ghcr`, `purrcafe-deployed`, `purrcafe-percolator`, `radicale-data-mount`, `roastery-deploy-checkout`, `roastery-scrutiny-collector`, `runbook-2026-10-14-handoff`, `runbook-pr43-merged`, `scrutiny-host-labels`, `tunnel-forwarded-headers`, `upgrade-gate-records-install` (all `claude/`), and `codex/opencloud-radicale`: 0 commits ahead of `main`, merged. Stale.
- 11 `dependabot/*` branches: heads of the open Dependabot PRs above.

## Key decisions
- 2026-10-12 · Every image pinned by tag and digest; risky upgrades held behind a gate · [runbook.md](runbook.md) "Every image pinned by tag and digest"
- 2026-10-12 · Nodes fetch `main`, never pull; reviewed commits deployed with `fleet.py` · [runbook.md](runbook.md) "Reviewed deployments"
- 2026-10-12 · The old file app is retired; OpenCloud + Radicale replace it · [runbook.md](runbook.md) 2026-10-12 "decommissioned" entry
- 2026-10-12 · barista's uid comes from `PUID`, not a hardcoded 1000 · [runbook.md](runbook.md) 2026-10-11 entry
- 2026-10-13 · Bots get cat-breed names (`scottishfold`, `pixiebob`, `sphynx`) · [runbook.md](runbook.md) "Bots have cat names"; [AGENTS.md](AGENTS.md)
- 2026-10-13 · Upgrade gates remember the installed version · [runbook.md](runbook.md) "Upgrade gates remember"
- 2026-10-14 · meowGram and purrCafe run on percolator from their published images · [runbook.md](runbook.md) 2026-10-14 entries
- 2026-10-15 · persianPerch runs its release image; cellar no longer builds it · [runbook.md](runbook.md) 2026-10-15 entry
- 2026-10-21 · pourOver joins grinder as an optional app · [runbook.md](runbook.md) 2026-10-21 entry
- 2026-10-23 · meowGram 2.0.0 with bots off; the dump is the rollback · [runbook.md](runbook.md) 2026-10-23 entry

## How to resume
1. Read [AGENTS.md](AGENTS.md), the runbook Backlog and its newest entries, [docs/MAP.md](docs/MAP.md); `git status`, `git log -20`.
2. Fix CI: put pourOver's real digest in `stacks/grinder/pourover/docker-compose.yml` once pourOver #7 is released (`python3 scripts/images.py ghcr.io/purrmonster/pourover:0.1.0`).
3. Backups: fresh repository on roastery, sieve's restic password, `sudo ./backup.sh nightly` per node, restore test.
4. Review #78 and #79; then Dependabot PRs after reading release notes.
5. Then, in order: meowGram 2.0.0 rollout, persianPerch, the Cloudflare pass, `fleet.py deploy` on sieve and cellar for records.

## Decisions to remake
- Open WebUI → roastery's LLMs: machine-to-machine auth still undecided (Backlog, 2026-10-07 entry); pourOver's Basic-auth service account may settle it.
- barista in the `docker` group (root without a password): still listed as a decision (Backlog).
- cellar's Samba: compose exists, nothing uses it, port closed; decide shares or drop it.
- meowGram bots: off on purpose; turning them on is an auth change needing its own PR.
- AGENTS.md says never delete branches, yet ~20 merged branches are piling up: a cleanup rule may be worth deciding.

## Questions for Roastmaster
- Are backups running on any node since the 2026-10-12 reinstall, and was sieve's `RESTIC_PASSWORD` pasted?
- purrCafe's Backlog line (Cloudflare route `cafe.${DOMAIN}` missing, per [e710d4f](https://github.com/purrMonster/purrbrews-containers/commit/e710d4f)) is no longer in the Backlog: done, or lost in a merge?
- Has meowGram 2.0.0 been rolled out on percolator yet?
- Has the Cloudflare pass for opencloud, radicale, cafe and meow happened?
- Is the fetch-only timer installed on any node?
- Are mochaPot's and grinder's new SSH host keys confirmed at the console (2026-10-14 entry)?
- May the 20 merged branches above be deleted?
- Is roastery joining the fleet (Backlog "Remaining node") still a goal, and is purrBrews-infra archived?

## Card history
- 2026-10-23 · created by Claude (Opus 5.5)
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
