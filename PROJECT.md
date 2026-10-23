---
project: purrbrews-containers
status: active
status_reason: Fleet rebuilt 2026-10-12/13 and running; backups, mail relay, tunnel routes and new apps still being brought up
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
