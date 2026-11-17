---
project: purrbrews-containers
status: active
status_reason: Being rebuilt after the house move; branch claude/stack-rebuild approved, not yet pushed; nothing deployed yet
resume_trigger: n/a
last_activity: 2026-11-17
last_reviewed: 2026-11-17
repo: https://github.com/purrMonster/purrbrews-containers
related: ["[[purrbrews-bootstrap]]", "[[persianPerch]]", "[[meowGram]]", "[[purrCafe]]", "[[pourOver]]"]
tags: [project]
---

# purrBrews fleet (purrbrews-containers)

## What it is
Infrastructure as code for the purrBrews home lab: the Docker Compose stacks, grouped by
what they do, the scripts every node shares, and one small folder per machine saying which
apps it runs. Five Debian nodes. Stack: Debian 13, Docker Compose, Traefik, Authelia +
LLDAP, restic, Bash and Python tooling, tests in GitHub Actions. Index: [docs/MAP.md](docs/MAP.md).

## Current state
| Area | State | Evidence |
|---|---|---|
| Code | Restructured by stack; roastery's jobs re-homed (LiteLLM, CPU Immich ML); backups and node setup incomplete | [docs/carry-over-map.md](docs/carry-over-map.md) |
| Release | None: branch `claude/stack-rebuild`, approved 2026-11-17, not yet pushed | [runbook.md](runbook.md), 2026-11-17 |
| Deployment | Nothing from the new layout has run on a machine. The old fleet is frozen at tag `freeze-2026-10` | [docs/migration-plan.md](docs/migration-plan.md) |
| Tests / CI | Offline tests pass locally (87 of 88; one cannot load on Python 3.10; three root-only not run). No CI run on this layout yet | runbook, 2026-11-16, Evidence |

## Open points
1. Push the approved branch (how is the owner's call: a PR, or a merge to `main`).
2. W1: the payload that finishes a node after purrbrews-bootstrap.
3. W2: the backup repository on cellar; backups do not work until then.
4. The provider and model for LiteLLM (any OpenAI-compatible endpoint until then).
5. Voice: engines on all three ThinkCentres, not yet designed.

## Key decisions
- 2026-11-16 · Rebuild organised by stack, one home per app · [runbook](runbook.md)
- 2026-11-16 · roastery out; a cloud model through LiteLLM replaces the local LLMs · [runbook](runbook.md)
- 2026-11-16 · The network node is a ThinkCentre by the router · [runbook](runbook.md)
- 2026-11-16 · Bootstrap from the purrbrews-bootstrap repository · [runbook](runbook.md)
- 2026-11-17 · Proposals P1 to P9 confirmed; every app starts empty; voice engines on all three ThinkCentres · [runbook](runbook.md)
- Earlier decisions (public repo, secrets born on the node, a Traefik per node, restic design, image pins, reviewed deploys) still hold: [deprecated/runbook.md](deprecated/runbook.md)

## How to resume
1. Read [AGENTS.md](AGENTS.md), the runbook's Backlog and newest entry, [docs/MAP.md](docs/MAP.md); `git status`, `git log -20`.
2. Follow [docs/migration-plan.md](docs/migration-plan.md) from the first unticked phase.

## Card history
- 2026-11-16 · rewritten by Claude (Fable 5.2) for the rebuild; the earlier card is in `deprecated/PROJECT.md`
