# Migration plan

From the frozen pre-move fleet to a working fleet in the new house, on the
hardware in [hardware.md](hardware.md), with the layout in
[carry-over-map.md](carry-over-map.md). Written 2026-11-16 on branch
`claude/stack-rebuild`.

**Where things stand.** The repo is restructured and its offline tests pass.
Nothing from this branch has run on a machine. roastery is out, so there are
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
| W1 | The fleet's payload for purrbrews-bootstrap: static address and derived MAC, the checkout in `/opt/purrbrews`, `/opt/purrbrews/.env`, data directories, the fetch-only timer | `deprecated/init/` | Phase 1 |
| W2 | The repository account on cellar (SFTP-only user, one folder, per-node keys), and the hub scripts without wake-on-LAN or the `roastery` remote | `deprecated/stacks/roastery/backup-target`, `stacks/backup/restic` | Phase 5 |
| W3 | The recovery kit, built from americano | `deprecated/stacks/roastery/flask`, `deprecated/docs/flask.md` | Phase 5 |
| W4 | Voice: Whisper, Piper, a satellite per ThinkCentre | nothing yet | Phase 9 |
| W5 | Joining a node to the tailnet (it was a step of the old init) | `deprecated/init/purrbrews-init.sh`, `step_tailscale` | Phase 10 |
| W6 | Node READMEs rewritten; roastery wording swept out of app READMEs and comments | the old READMEs, in place | As each node comes up |

## Phase 0: save what exists

Before any disk is wiped. Whatever data the old fleet still has is on the
nodes' own disks. roastery, which held the backup repository, was wiped on
2026-10-07, and the old project card (2026-10-27) still listed "backups after
the reinstall" as open, so assume there is no usable backup until step 3 says
otherwise.

1. (owner) Decide, app by app, restore or start empty. Suggested: restore what
   the household made (Vaultwarden, Immich, Paperless, OpenCloud, Radicale,
   Actual Budget, Mealie, Vikunja, meowGram, Home Assistant); start the rest empty.
2. For every node that still boots: copy `/srv/data`, `/srv/dumps`,
   `/opt/purrbrews/.env`, every `.env.local` and `secrets.env.local`, and
   `/etc/purrbrews` to one of the old 1 TB HDDs in the USB dock. Restored data
   only opens with the secrets it was made with (database passwords,
   OpenCloud's and Vaultwarden's keys).
3. Check whether roastery's `C:\purrbrews\restic` or the Google Drive copy still
   holds a repository, and keep the restic password and the rclone crypt
   password and salt wherever they are (cellar's old `restic/secrets.env.local`,
   the flask vault).
4. Database apps: a dump beats a copied data directory. If a node is up, run
   its old `sudo ./backup.sh dump` first and copy the dumps too.

**Done when** the HDD holds a copy per node and a note of what was taken, and
the second HDD holds a copy of the first. **Way back:** nothing is changed in
this phase.

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
4. Bring up purrbrews-bootstrap on americano from its release image; put
   americano's public key in it; note the TLS pin.
5. **W1, the payload.** What purrbrews-bootstrap already does and what is left:

   | Old init step | Now |
   |---|---|
   | hostname, timezone, apt, ops user, SSH keys, SSH hardening, power, journald, Docker, firewall | purrbrews-bootstrap's own steps |
   | repo (clone to `/opt/purrbrews`), directories (`/srv/data`, `/srv/media`, `/srv/dumps`) | payload |
   | `/opt/purrbrews/.env` (`NODE`, `NODE_IP`, `PUID`, `PGID`, `DATA_DIR`, `MEDIA_DIR`) | payload. `_lib` reads `NODE` from it to know which node it is on |
   | network (static address, MAC derived from the node name, rollback if the gateway stops answering) | payload, from `net-apply.sh` and `node-mac.sh` |
   | timers (daily fetch, never a pull) | payload, from `purrbrews-pull.sh` |
   | tailscale | phase 10 |

   The payload is public (anyone on the LAN can download it), so it carries no
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

1. Set percolator up. If its data disk still holds the old `/srv/data`, do not
   let the installer touch that disk; mount it read-only somewhere else until
   phase 6.
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

1. **W2.** On cellar: an SFTP-only account whose only folder is the repository
   on the NVMe, with one line per node's backup key, the way the dump store is
   already set up (`dump-store-setup.sh` is the model;
   `deprecated/stacks/roastery/backup-target/setup.ps1` is what it replaces).
2. **W2.** In `stacks/_lib/restic-env.sh` and `stacks/backup/restic`: drop
   wake-on-LAN, rename what is named after roastery, let the hub read its own
   repository by path, and rewrite the README. Extend the tests; the three
   root-only ones must pass in CI.
3. The repository: restore it from Drive if phase 0 found one worth keeping
   (the drive-sync guard refuses to overwrite Drive from an empty repository,
   by design), otherwise `restic init` and a new password. Either way the
   password and the crypt keys go to the recovery kit the same day.
4. Per node: `sudo ./backup.sh install`, `keys`, authorise the lines on cellar,
   `doctor`, then `nightly` by hand once, then `enable`.
5. A restore test of one node's snapshot into a scratch directory, and the
   Drive copy read back.
6. The offline copy: one HDD in the dock after each successful prune, the two
   alternating. Run a long SMART self-test on both first.
7. **W3.** The recovery kit, from americano.

**Done when** two nights in a row every node has a fresh snapshot, the morning
check is quiet, a restore test passed, and Drive holds the same repository.
**Way back:** `sudo ./backup.sh disable` per node; nothing else reads the repository.

## Phase 6: percolator, the household apps

One app at a time, in `node.conf` order: radicale, opencloud, vaultwarden,
immich, paperless, mealie, vikunja, meowgram, actualbudget, freshrss, purrcafe.

For each: restore its data and its `secrets.env.local` first if it is one of
the restored apps (phase 0), bring it up, run its README's checklist, add or
confirm its Gatus check, and let one night's backup pass before the next app
with data.

- OpenCloud: the migration rehearsal the old Backlog asked for still applies to
  restored data.
- meowGram: restored 1.1.0 data and the pinned 2.0.0 means a dump first; it is
  the only way back.
- Immich: faces and search wait for phase 8.

**Done when** each app's checklist is ticked in the runbook with what was seen.
**Way back:** per app, `./compose.sh <app> down` and its data directory from
the night before.

## Phase 7: mochaPot, home

1. Set mochaPot up through its USB Ethernet adapter. `pihole-secondary` first;
   check it answers and that sieve's DHCP hands out both resolvers.
2. `homeassistant` (restore its config if kept), set `trusted_proxies` in its
   UI to the `proxy` subnet and sieve's address; `musicassistant`; `traefik`.
   **Check** the merged Traefik with host-networked apps: all three pages open
   through it.
3. `komodo-periphery`, `scrutiny-collector` (it uses
   `nodes/mochaPot/scrutiny-collector.yaml` for the SanDisk), the kiosk
   (`stacks/home/kiosk`).

**Done when** the three pages open by name, the kiosk shows the dashboard after
a reboot, and stopping sieve's Pi-hole for a minute leaves name resolution working.

## Phase 8: grinder, automation and AI

1. (owner) Choose the cloud provider and model; make an API key for the fleet
   with a spending limit.
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

Not designed yet. The owner's outline: each ThinkCentre has a USB speaker and
a conference-room mic and runs speech-to-text and text-to-speech locally, with
Home Assistant on mochaPot deciding what to do.

To decide first: which Whisper model the i3s can run in real time; whether all
three machines run the engines or percolator only listens and speaks; the wake
word; and how audio devices are passed to a container on Debian. Then a
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
