# purrBrews runbook

Dated decisions for this repo, newest first, and the Backlog. Each entry says
what, why, and how to undo it. Rules for writing here are in
[AGENTS.md](AGENTS.md): one writer at a time; new entries go below the Backlog;
a box is ticked only with the evidence on the same line.

This runbook starts with the rebuild after the house move. Everything before
2026-11-16 is in [`deprecated/runbook.md`](deprecated/runbook.md), unedited:
when a comment in the code says "runbook, 2026-09-…" or "2026-10-…", it means
that file.

## Backlog / open items

Order follows [docs/migration-plan.md](docs/migration-plan.md).

**To decide (owner)**

- [x] Confirm or change the proposals in the 2026-11-16 entry below (P1 to P9): all confirmed (owner, 2026-11-17)
- [x] Restore or start empty, app by app (plan, phase 0): every app starts empty (owner, 2026-11-17)
- [ ] The cloud provider and model behind LiteLLM, and a spending limit on its key (phase 8). Still open; LiteLLM now takes any OpenAI-compatible endpoint until then (owner, 2026-11-17)
- [x] Voice: engines on all three ThinkCentres (phase 9) (owner, 2026-11-17)
- [x] Review branch `claude/stack-rebuild`: approved (owner, 2026-11-17). Push and merge still to be done

**Phase 0: save what exists**

- [x] Back up what is needed from the old nodes: done, by the owner's own means (owner, 2026-11-17). Not seen by Claude; nothing is restored from it in this plan
- [x] An old restic repository: not needed, every app starts empty; phase 5 makes a new one (owner, 2026-11-17)

**Phase 1: foundations**

- [ ] The machine checks in `docs/hardware.md` (`lsblk`, M.2 SATA boot on a ThinkCentre, x360 memory slots, USB Ethernet) (owner)
- [ ] The router's address, and that its DHCP turns off (owner)
- [ ] purrbrews-bootstrap running on americano with americano's key in it (owner)
- [ ] W1: write the payload (static address and derived MAC, checkout, `/opt/purrbrews/.env`, directories, fetch-only timer) from `deprecated/init/`
- [ ] Rehearse one fresh machine through the one-liner, twice
- [ ] Close the open Dependabot PRs once this branch is merged; they target the old paths (owner)
- [ ] First CI run on this layout (PR #92). The three root-only backup tests passed locally as root on 2026-11-17 (see that entry); CI is the record
- [ ] n8n 3.x and OpenCloud 9.x: majors held back in the 2026-11-17 image update; read their upgrade notes and decide before phases 6 and 8 (owner)

**Phases 2 to 4: sieve, cellar, percolator's identity**

- [ ] sieve: DNS answering, an alert reaching the phone, then the DHCP handover from the Humax router
- [ ] cellar: Komodo and Scrutiny up; sieve's agents registered; the merged collector shows the node and its one disk
- [ ] percolator: Traefik, CrowdSec, LLDAP with its service accounts (`scottishfold`, `pixiebob`, `sphynx`, the `llm_api_group` accounts), Authelia
- [ ] Purelymail app password for the mail relay (owner); the relay has never run

**Phase 5: backups**

- [ ] W2: the repository's SFTP account on cellar; hub scripts and README without roastery; tests extended
- [ ] A new repository (`restic init`); password and crypt keys into the recovery kit the same day
- [ ] Every node: install, keys, doctor, one nightly by hand, enable
- [ ] A restore test, and the Drive copy read back
- [ ] Long SMART self-test on both old HDDs before they hold the offline copies
- [ ] W3: the recovery kit rebuilt from americano

**Phases 6 to 8: the apps**

- [ ] percolator's household apps, one at a time, empty, each with a night's backup behind it
- [ ] mochaPot: secondary Pi-hole, Home Assistant with `trusted_proxies` for the new subnet, the merged Traefik checked with host-networked apps, kiosk
- [ ] grinder: LiteLLM healthy and `llm.${DOMAIN}` refusing a request without credentials; Open WebUI answering; Immich ML reachable from percolator only
- [ ] pourOver's planning tried against the cloud model before it is switched on
- [ ] Gatus: a check for Immich ML's port

**Phases 9 to 11**

- [ ] W4: voice designed (Whisper and Piper on all three ThinkCentres) and one room proven
- [ ] W5: tailnet join; the Remote Desktop grant out of `tailscale/policy.hujson`
- [ ] Cloudflare tunnel routes in one pass; then the visitor-address check
- [ ] Two-factor in Authelia once every account has enrolled
- [ ] W6: node READMEs rewritten; roastery wording swept from app READMEs and comments
- [ ] Carried from the old Backlog, still open: `barista` in the `docker` group; Samba, shares or gone; a bot identity for agents' commits; the merged branches on GitHub (owner)

## 2026-11-17 — The owner's answers to the 2026-11-16 entry

**What.** The owner answered the open decisions in the Backlog (in chat,
2026-11-17 21:28 IST). Recorded here and applied on `claude/stack-rebuild`.

- **P1 to P9 confirmed** as written below: machines, addresses, the repository
  on cellar, Immich ML on grinder, LiteLLM's shape and route, the secondary
  Pi-hole on mochaPot, the `proxy` network, the stack groups.
- **Every app starts empty.** Nothing is restored from the old fleet. The
  owner has already backed up what is needed (not seen by Claude). So phase 0
  of the plan is done, phase 5 starts a new restic repository, and phase 6
  brings each app up empty. meowGram 2.0.0 needs no dump first on an empty install.
- **The LLM provider is still to be chosen.** Until then LiteLLM is set up for
  any OpenAI-compatible endpoint: `LLM_UPSTREAM_API_BASE` (new),
  `LLM_UPSTREAM_MODEL` (now the bare model id) and `LLM_UPSTREAM_API_KEY`, all
  asked for by `./setup-secrets.sh`. LiteLLM's `openai/` prefix is in the template.
- **Voice runs the engines (Whisper and Piper) on all three ThinkCentres**,
  percolator included.
- **The branch is approved.** Pushing is public, so it waits for the owner to
  say how: push the branch and open a PR, or merge to `main` and push.

**Pushed** as PR #92 (owner chose "push and open a PR").

**Images updated** (owner: "update the containers along the way"). Every app
starts empty, so no data has to survive these upgrades. Every pinned image is
on its newest release as of 2026-11-17, read from each registry's tag list,
with a few limits:

- **Databases stay on their major version** (Postgres 16 and 18, PostGIS on
  16, Mongo 7, pgvector on pg16): the apps that use them pin those majors.
- **Apps with a newer major were held to their current one:** n8n stays on
  2.x (3.3.0 exists) and OpenCloud on 7.x (9.x exists; Dependabot ignores its
  majors by policy). Both are open in the Backlog.
- **Pairs moved together:** Immich server and ML to v3.4.1 (Immich's own
  compose keeps the same Postgres image); Komodo Core and Periphery to 2.3.4;
  the Scrutiny hub and collector to v0.10.0; both Pi-holes to 2026.11.0;
  Meilisearch to v1.55.0, the version Karakeep 0.35.0's compose pins (the
  Dependabot ignore rule moved with it).
- **Floating tags re-resolved to today's digest:** karakeep-chrome `release`,
  unbound `main`, samba `latest`.
- **The embedding worker's base** moved to `python:3.14.10-slim`, still 3.14,
  because torch's wheels decide when 3.15 is safe.

Digests come from `scripts/images.py`, one image at a time; each has a
linux/amd64 build. Release notes were not read for each image; nothing has
run on a node.

**Evidence.** In a cloud workspace with Python 3.13, restic, rclone and
sqlite3, on the commit with the image updates:

- `python3 -m unittest discover -s tests`, as a normal user: 90 run, OK, 3
  skipped (the root-only tests).
- The same as root: 90 run, OK, 8 skipped (the tests that refuse root). The
  three root-only backup tests passed: dump-and-files into a local repository,
  drive-sync refusing an empty or different repository, and glob dumps named
  by path. That is the first run of those three since the layout changed.
- `test_groom_record` loads and passes on 3.13.
- `shellcheck --severity=warning` is clean.

**How to undo.** Revert this entry's commits. The decisions themselves are the owner's.

**Next step.** The owner reviews and merges PR #92 once CI is green; then
phase 1: the machine checks, the router's facts, and W1, the bootstrap payload.

## 2026-11-16 — Rebuild after the move: stack layout, roastery out, cloud AI in (session handoff)

**What.** The owner asked for the repo to be analysed, then for an app-by-app
carry-over map, a hardware rearrangement, a complete migration plan, the old
files archived under `deprecated/` (the old runbook included) and a new runbook,
all on a new branch. Done on `claude/stack-rebuild` (branched from `main` at
`375c274`), in commits finished on 2026-11-17 IST. **Not pushed**: a push is
public and was not asked for.

**Decided by the owner (this session and before it)**

- D1. The fleet is rebuilt after the move, on the hardware at hand, organised
  by stack (network, identity, fleet management and so on) instead of by node.
- D2. roastery is out of commission until further notice: its 3080 died in the
  move. The local LLMs are down with it.
- D3. AI goes through a light web wrapper around a cloud model: a LiteLLM proxy
  and a small UI.
- D4. The network node is a ThinkCentre in the living room next to the router,
  not the laptop. A tablet or an ESP32 screen can be added there later.
- D5. Bootstrap comes from the separate purrbrews-bootstrap repository; this
  repo's `bootstrap/` is archived.
- D6. Reuse whatever can be reused (configs, container code); archive the rest.
- D7. Lay the hardware out from the old runbook and the hardware the owner
  listed. The file the owner pointed to, `infrastructure.md`, could not be
  found: not in this repo or its history, not in purrBrews-infra, not in the
  Project. The old runbook only cites it.
- D8. The LAN is `192.168.1.x` behind a Humax router (Tata Play Fiber) whose
  DHCP can be turned off.
- D9. Each of the three ThinkCentres sits in a different room with a USB
  speaker and a conference-room mic, and runs Whisper and Piper locally.

**Proposed by Claude, built into the branch, waiting for the owner's yes**

- P1. Machines: sieve, percolator and cellar stay the three ThinkCentres,
  mochaPot the x360 laptop, grinder the x360 board. Memory 8/16/16/8/16 GB
  (cellar gains a stick). Disks as in `docs/hardware.md`; the second 1 TB NVMe
  goes to cellar.
- P2. Node names, roles and last octets stay: `.10` to `.14`. Gateway assumed
  `192.168.1.1`.
- P3. The restic repository moves to cellar's NVMe, still over SFTP. Google
  Drive and the two old HDDs remain the second and offline copies.
- P4. Immich's machine learning runs on grinder's CPU.
- P5. LiteLLM runs on grinder with no master key and no database, reachable on
  grinder's own Docker network and, from elsewhere, through Traefik and
  Authelia with a service account (the pattern roastery's route used). Open
  WebUI stays as the "small UI". One model name, `default`.
- P6. The route is `llm.${DOMAIN}` and the LLDAP group `llm_api_group`
  (were `ollama.…` and `ollama_api_group`).
- P7. The secondary Pi-hole stays on mochaPot, for its battery.
- P8. Every node's Docker network is called `proxy` with a pinned
  `PROXY_SUBNET`, so an app can move nodes without an edit. This also answers
  the old Backlog's proposal about `fleet.py deploy` failing at the firewall
  on a node with no pinned subnet.
- P9. Stack groups: network, identity, mail, apps, home, automation, ai,
  monitoring, fleet-management, backup. Node definitions under `nodes/`.

**What changed, in short** (the full list is `docs/carry-over-map.md`)

- Every app has one home, `stacks/<group>/<app>`; a node is `nodes/<node>/`.
  Per-node copies of Traefik (three of them), Periphery, the Scrutiny
  collector and the restic settings became one folder each.
- `_lib` finds apps by name and refuses an app the node's `node.conf` doesn't list.
- New: `stacks/ai/litellm`. Rewritten: `stacks/ai/immich-ml` (CPU image).
  Repointed: Open WebUI, pourOver, Immich, Authelia, Gatus.
- Archived, unedited, at their old paths under `deprecated/`: the old runbook,
  README, project card and map; `bootstrap/`; `init/`; all of
  `stacks/roastery`; the superseded per-node copies; the PowerShell and init tests.
- New docs: `docs/carry-over-map.md`, `docs/hardware.md`,
  `docs/migration-plan.md`, `docs/MAP.md`, `README.md`, `PROJECT.md`, this file.
  `AGENTS.md`: pointers to the new layout only.

**Evidence**

- `python3 -m unittest discover -s tests`: 88 run, 87 pass, 3 skipped, 1 error.
  The skipped three are the root-only backup tests (edited for the layout, not
  run: they need root and restic). The error is `tests/test_groom_record.py`
  failing to import on Python 3.10 (`datetime.UTC` needs 3.11); it did the same
  on `main` on this machine.
- `shellcheck --severity=warning` over every `.sh` in `stacks`, `nodes`,
  `tailscale`: clean.
- `python3 scripts/fleet.py validate`: "Validated 5 nodes and 54 apps".
- Digests read from ghcr.io on 2026-11-16 with `scripts/images.py`:
  `berriai/litellm:v1.83.14-stable`, `immich-machine-learning:v3.3.3`.

**Not done, and not verified**

- Nothing ran on a node. No `docker compose config`, no render with real
  settings, no UFW. The merged Traefik on mochaPot (host-networked apps), the
  one-or-two-disk collector, LiteLLM and CPU Immich ML are untested.
- Backups do not work as they stand: `BACKUP_REPOSITORY` points at an account
  on cellar that does not exist, and the hub's scripts and README still
  describe waking roastery (W2).
- The payload that finishes a node after purrbrews-bootstrap is not written (W1).
- Voice is not designed (W4). The tailnet join step is archived with init (W5).
- Node READMEs are the old ones with a banner. Many app READMEs and comments
  still mention roastery (W6). `tailscale/policy.hujson` still grants Remote Desktop.
- The hardware table is from lists, not from the machines.

**How to undo.** The branch is the whole change: don't merge it, or
`git revert` its commits. `main` and tag `freeze-2026-10` are untouched.

**Next step.** The owner reads the proposals above and `docs/hardware.md`,
then phase 0 of the plan (save what exists) before anything is reinstalled.
