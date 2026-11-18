# Migration plan

From the frozen pre-move fleet to a working fleet in the new house, on the
hardware in [hardware.md](hardware.md), with the layout in
[carry-over-map.md](carry-over-map.md). Written 2026-11-16 on branch
`claude/stack-rebuild`.

**Where things stand.** The repo is restructured and its offline tests pass.
Nothing from this branch has run on a machine. The owner's decisions of
2026-11-17 are in: the layout is confirmed and every app starts empty. roastery is out, so there are
no local LLMs, no backup repository and no bootstrap host until the phases
below replace them. Each phase says what it needs, what "done" means and how
to get back.

Rules that hold throughout ([AGENTS.md](../AGENTS.md)): one node at a time,
network first; never both DNS servers together; a change to a node needs the
owner's go-ahead; tick a line in the [runbook](../runbook.md) only with the
evidence beside it.

## What still has to be written

Code this plan depends on that does not exist yet. Everything else is in the repo.

| # | What | Built from | Needed by |
|---|---|---|---|
| W1 | The fleet's payload for purrbrews-bootstrap: static address and derived MAC, the checkout in `/opt/purrbrews`, `/opt/purrbrews/.env`, data directories, the fetch-only timer. **Written 2026-11-18** (`payload/`), not yet run on a machine | `deprecated/init/` | Phase 1 |
| W2 | **Written 2026-11-18** (`stacks/backup/restic/repo-setup.sh`, README). The repository account on cellar (SFTP-only user, one folder, per-node keys), and the hub scripts without wake-on-LAN or the `roastery` remote | `deprecated/stacks/roastery/backup-target`, `stacks/backup/restic` | Phase 5 |
| W3 | **Written 2026-11-18** (`recovery/`, [recovery-kit.md](recovery-kit.md)). The recovery kit, built from americano | `deprecated/stacks/roastery/flask`, `deprecated/docs/flask.md` | Phase 5 |
| W4 | Voice: Whisper, Piper, a satellite per ThinkCentre | nothing yet | Phase 9 |
| W5 | Joining a node to the tailnet (it was a step of the old init) | `deprecated/init/purrbrews-init.sh`, `step_tailscale` | Phase 10 |
| W6 | Node READMEs rewritten; roastery wording swept out of app READMEs and comments | the old READMEs, in place | As each node comes up |

## Phase 0: save what exists (done)

The owner decided that **every app starts empty** and has already backed up
what is needed from the old nodes (owner, 2026-11-17). Nothing in this plan restores from
the old fleet: no old data directory, secrets file or restic repository is
carried over. Phase 5 makes a new repository and phase 6 brings each app up
empty.

## Phase 1: foundations

1. (owner) The checks in [hardware.md](hardware.md), "To check on the machines",
   and the router's facts: its address, that its DHCP can be turned off, and
   where it lists leases.
2. (owner) Confirm or change the proposals in the runbook's 2026-11-16 entry
   (machine for each node, addresses, LiteLLM's shape). `stacks/fleet.env` and
   `docs/hardware.md` change with them.
3. Review this branch and merge it; close the open Dependabot PRs (they target
   the old paths). CI runs the root-only backup tests, which could not run
   where this was written.
4. Bring up purrbrews-bootstrap on americano from its release5. **W1, the payload:** written 2026-11-18, in [`payload/`](../payload/README.md).
   purrbrews-bootstrap does the general steps; `payload/purrbrews-node.sh` does
   the rest: the checkout, `/opt/purrbrews/.env`, the data folders, `/etc/hosts`,
   the daily fetch and, last, the static address with the node's fixed MAC.
   Addresses come from `stacks/fleet.env`. Serve it from americano as its README says.
so it carries no
   secret and not the domain, like this repo.
6. Rehearse on one machine that holds nothing yet: Debian 13 netinst with the SSH
   server, the bootstrap one-liner with the payload, then `ssh barista@<address>`.

**Done when** a fresh machine ends up with key-only SSH, Docker, UFW, its static
address, the checkout and `/opt/purrbrews/.env`, twice in a row from the same
command. **Way back:** reinstall; nothing else depends on it yet.

## Phase 2: sieve, the network

Needs: phase 1. The router still does DHCP and DNS until step 5.

1. Set sieve up (ThinkCentre, living room, wired to the router). In `nodes/sieve`:
   `./setup-secrets.sh`, `sudo ./firewall.sh`.
2. `unbound`, then `pihole`, as DNS only. From americano: `dig @192.168.1.10`
   for a public name (recursion) and, after step 3, a local one.
3. `ntfy`, `traefik-edge`, `gatus`. Send a test alert and see it on the phone:
   monitoring is the last thing allowed to break.
4. `netalertx`, `komodo-periphery` and `scrutiny-collector` can wait for phase 3.
5. **DHCP handover.** Turn DHCP off on the Humax router, then
   `bash stacks/network/pihole/enable-dhcp.sh --routers-dhcp-disabled` on sieve.
   Reconnect one phone and one laptop; check lease, gateway and resolver.
6. `cloudflared` once percolator has something to publish (phase 4).

**Done when** a device that joins the Wi-Fi gets its lease and DNS from sieve,
Gatus is green for what exists, and an alert reaches the phone. **Way back:**
`./compose.sh pihole down` and turn the router's DHCP back on; clients fall
back within a lease renewal, sooner if reconnected.

## Phase 3: cellar, fleet management

1. Set cellar up with its 1 TB NVMe and second memory stick. `komodo`,
   `scrutiny`, `traefik`.
2. Copy Komodo Core's public key to sieve; bring up `komodo-periphery` and
   `scrutiny-collector` there. **Check** the merged collector: the node appears
   in Scrutiny under its name with its one disk.
3. Leave `smb` and `persian-perch` out (optional in `fleet.json`). Leave backups
   for phase 5.

**Done when** Komodo lists cellar and sieve, and Scrutiny shows both nodes'
disks. **Way back:** `./compose.sh --all down` on cellar; nothing depends on it yet.

## Phase 4: percolator, ingress and identity

No household data yet: that waits for backups (phase 5).

1. Set percolator up. Every app starts empty, so its data disk is wiped like
   the system disk; check first that the owner's backup of it is done.
2. `traefik-ingress`, `crowdsec`.
3. `mail-relay`, if the Purelymail app password exists (owner). Without it
   Paperless, Vikunja and Vaultwarden will not start in phase 6.
4. `lldap`, then `stacks/identity/lldap/lldap-bootstrap.sh`; create the service
   accounts (`scottishfold`, `pixiebob`, `sphynx`, one LLM account per caller in
   `llm_api_group`). `authelia`.
5. On sieve: `./render-configs.sh` and recreate Pi-hole so the new names
   resolve; add cellar's and sieve's addresses to `FORWARD_AUTH_CLIENTS` if they
   changed; `sudo ./firewall.sh` on percolator.
6. `homepage`, then `komodo-periphery` and `scrutiny-collector`.

**Done when** `authelia.${DOMAIN}` signs a person in, an admin page on sieve
and one on cellar ask for that sign-in and let an admin through, and a
household account is refused there. **Way back:** the other nodes' pages are
reachable on their own ports while Authelia is down, as designed.

## Phase 5: backups, on cellar

The one phase with real code to write first (W2, W3). Until it is done, no
node holds data that exists nowhere else.

1. **W2, written 2026-11-18.** The order to switch it on is in
   [stacks/backup/restic/README.md](../stacks/backup/restic/README.md), "Tying it
   together": `backup.sh install` on cellar and its secrets, then each node's
   `install` and its line in `restic/backup.keys`, then `repo-setup.sh` and
   `dump-store-setup.sh` on cellar.
2. Before that, on cellar: `findmnt /srv` and `df -h /srv` show the NVMe, and
   `sudo ./restic/repo-setup.sh --check` prints the keys it would install.
3. A new repository: `restic init` with a new password (every app starts
   empty, so nothing is restored). If the old Drive copy is still there, move
   it aside first: the drive-sync guard refuses to overwrite a different
   repository on Drive, by design. The password and the crypt keys go to the
   recovery kit the same day.
4. Per node: `sudo ./backup.sh install`, `keys`, authorise the lines on cellar,
   `doctor`, then `nightly` by hand once, then `enable`.
5. A restore test of one node's snapshot into a scratch directory, and the
   Drive copy read back.
6. The offline copy: one HDD in the dock after each successful prune, the two
   alternating. Run a long SMART self-test on both first.
7. **W3, written 2026-11-18.** The recovery kit, from americano, the same day the
   new repository's keys exist: Ventoy on stick B, `recovery/make-flask.sh`, the
   vault with `fill-vault.sh`, the paper, one offline boot of each stick
   ([recovery-kit.md](recovery-kit.md), "Building it").

**Done when** two nights in a row every node has a fresh snapshot, the morning
check is quiet, a restore test passed, and Drive holds the same repository.
**Way back:** `sudo ./backup.sh disable` per node; nothing else reads the repository.

## Phase 6: percolator, the household apps

One app at a time, in `node.conf` order: radicale, opencloud, vaultwarden,
immich, paperless, mealie, vikunja, meowgram, actualbudget, freshrss, purrcafe.

Every app starts empty (owner, 2026-11-17). For each: bring it up, run its
README's checklist, add or confirm its Gatus check, and let one night's backup
pass before the household puts anything into the next one.

- OpenCloud and the other apps with upgrade gates record their version on a
  fresh install; nothing needs acknowledging.
- meowGram: an empty install of 2.0.0 needs no dump first.
- Immich: faces and search wait for phase 8.

**Done when** each app's checklist is ticked in the runbook with what was seen.
**Way back:** per app, `./compose.sh <app> down` and its data directory from
the night before.

## Phase 7: mochaPot, home

1. Set mochaPot up through its USB Ethernet adapter. `pihole-secondary` first;
   check it answers and that sieve's DHCP hands out both resolvers.
2. `homeassistant`, onboarded fresh, set `trusted_proxies` in its
   UI to the `proxy` subnet and sieve's address; `musicassistant`; `traefik`.
   **Check** the merged Traefik with host-networked apps: all three pages open
   through it.
3. `komodo-periphery`, `scrutiny-collector` (it uses
   `nodes/mochaPot/scrutiny-collector.yaml` for the SanDisk), the kiosk
   (`stacks/home/kiosk`).

**Done when** the three pages open by name, the kiosk shows the dashboard after
a reboot, and stopping sieve's Pi-hole for a minute leaves name resolution working.

## Phase 8: grinder, automation and AI

1. (owner) Choose the provider and model; make an API key for the fleet with
   a spending limit. Still open (2026-11-17): LiteLLM takes any endpoint that
   speaks the OpenAI API, so the choice is three settings when it's made.
2. Set grinder up. `postgres-vector`, `embedding-worker`, `n8n`.
3. `litellm` ([its README](../stacks/ai/litellm/README.md)): healthy, and
   `llm.${DOMAIN}` answers 401 to a request without credentials. Then
   `openwebui`: the model `default` is listed and answers.
4. `immich-ml`; `sudo ./firewall.sh`; from percolator `curl` its port, from
   sieve confirm it is refused. Start Immich's jobs and watch grinder's load for
   a day.
5. The self-tracking apps, `esphome`, `speedtest-tracker`, `traefik` and the agents.
6. `pourover`, last and only if wanted (`--include-optional pourover`): try
   its planning against the cloud model with one harmless message first.

**Done when** a chat in Open WebUI gets an answer, the provider's usage page
shows only that traffic, and new photos get faces. **Way back:** `litellm down`
costs nothing; the apps that call it queue or show an error.

## Phase 9: voice (W4)

Not designed yet. Decided: each ThinkCentre (sieve, percolator, cellar) has a
USB speaker and a conference-room mic and runs both engines itself, Whisper
for speech-to-text and Piper for text-to-speech, with Home Assistant on
mochaPot deciding what to do (owner, 2026-11-17).

To decide first: which Whisper model the i3s can run in real time, with
percolator's load in mind, since it runs the engines alongside the household
apps; the wake word; and how audio devices are passed to a container on Debian. Then a
`stacks/voice/` group, each image pinned by tag and digest, and one room
proven end to end before the other two.

## Phase 10: the ways in from outside

1. **W5**, the tailnet: join each node (UFW stays the only gate, as before),
   americano and the phone. Take the Remote Desktop grant out of
   `tailscale/policy.hujson`.
2. The Cloudflare tunnel's routes in one pass (opencloud, radicale, cafe, meow,
   and the rest of the template), then the check that tunnel visitors show
   their own address in the logs.
3. Two-factor in Authelia once every household account has enrolled; only then
   the tunnel "from Git" switch described in cloudflared's README.

## Phase 11: close out

- Rewrite each node README from what was actually done (W6) and take the banner off.
- Decide the leftovers from the old Backlog that still mean something:
  `barista` in the `docker` group; Samba, shares or gone; a bot identity for
  agents' commits; the merged branches on GitHub.
- When a GPU returns: llama-swap behind LiteLLM, Immich ML back on it.
- Delete `deprecated/` only when nothing in "Source" on the carry-over map is
  still waiting to be rebuilt; tag `freeze-2026-10` keeps it regardless.

## What was and was not verified on this branch

| | |
|---|---|
| Verified | `python3 -m unittest discover -s tests`: 87 pass. `shellcheck --severity=warning` over `stacks`, `nodes`, `tailscale`: clean. `scripts/fleet.py validate`: 5 nodes, 54 app slots. Image digests for LiteLLM and Immich ML read from the registry |
| Not run | The three root-only backup tests (they need root and restic; CI has both). One test file could not load on the machine used (it needs Python 3.11) |
| Not verified at all | Anything on a node: `docker compose config` for any stack, a render with real settings, UFW, the merged Traefik and collector, LiteLLM, Immich ML on a CPU, every hardware assumption |
