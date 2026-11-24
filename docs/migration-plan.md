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
| W2 | **Written 2026-11-18** (`stacks/backup/restic/repo-setup.sh`, README). The repository account on cellar (SFTP-only user, one folder, per-node keys), and the hub scripts without wake-on-LAN or the `roastery` remote | `deprecated/stacks/roastery/backup-target`, `stacks/backup/restic` | Phase 4 |
| W3 | **Written 2026-11-18** (`recovery/`, [recovery-kit.md](recovery-kit.md)). The recovery kit, built from americano | `deprecated/stacks/roastery/flask`, `deprecated/docs/flask.md` | Phase 4 |
| W4 | **Written 2026-11-18** (`stacks/voice/`, [voice.md](voice.md)). Voice: Whisper, Piper, a satellite per ThinkCentre | nothing yet | Phase 9 |
| W5 | **Written 2026-11-18** (the payload's `tailnet` step; [tailscale/README.md](../tailscale/README.md)). Joining a node to the tailnet (it was a step of the old init) | `deprecated/init/purrbrews-init.sh`, `step_tailscale` | Phase 10 |
| W6 | Node READMEs rewritten; roastery wording swept out of app READMEs and comments | the old READMEs, in place | As each node comes up |

## Phase 0: save what exists (done)

The owner decided that **every app starts empty** and has already backed up
what is needed from the old nodes (owner, 2026-11-17). Nothing in this plan restores from
the old fleet: no old data directory, secrets file or restic repository is
carried over. Phase 4 makes a new repository and phase 6 brings each app up
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
4. Bring up purrbrews-bootstrap on americano from its release image; put
   americano's public key in it; note the TLS pin.
5. **W1, the payload:** written 2026-11-18, in [`payload/`](../payload/README.md).
   purrbrews-bootstrap does the general steps; `payload/purrbrews-node.sh` does
   the rest: the checkout, `/opt/purrbrews/.env`, the data folders, `/etc/hosts`,
   the daily fetch and, last, the static address with the node's fixed MAC.
   Addresses come from `stacks/fleet.env`. Serve it from americano as its README
   says. The payload is public (anyone on the LAN can download it), so it
   carries no secret and not the domain, like this repo.
6. Rehearse on one machine that holds nothing yet: Debian 13 netinst with the SSH
   server, the bootstrap one-liner with the payload, then `ssh barista@<address>`.

**Done when** a fresh machine ends up with key-only SSH, Docker, UFW, its static
address, the checkout and `/opt/purrbrews/.env`, twice in a row from the same
command. **Way back:** reinstall; nothing else depends on it yet.

## Phase 2: sieve, the network

Needs: phase 1. The router still does DHCP and DNS until step 5.

1. Set sieve up (ThinkCentre, living room, wired to the router). In `nodes/sieve`:
   `./setup-secrets.sh`, `sudo ./firewall.sh`.
2. `unbound`, then `pihole`. **Pi-hole serves DHCP as soon as it starts**: its
   compose file always enables it (the node with `RESOLVER=primary` is the
   LAN's only DHCP server). So turn the router's DHCP off when Pi-hole first
   starts, or the two hand out leases side by side. (On 2026-11-19 it ran a
   night beside the router's: this step said "DNS only", which it never was.)
   From americano: `dig @192.168.1.10` for a public name (recursion) and, after
   step 3, a local one.
3. `ntfy`, `traefik-edge`, `gatus`. Send a test alert and see it on the phone:
   monitoring is the last thing allowed to break.
4. `netalertx`, `speedtest-tracker` (from grinder, 2026-11-23), `komodo-periphery` and
   `scrutiny-collector` can wait for phase 3.
5. **DHCP handover.** With the router's DHCP off,
   `bash stacks/network/pihole/enable-dhcp.sh --routers-dhcp-disabled` on sieve
   checks the range and gateway, restarts Pi-hole, and confirms it's listening
   on 67/udp.
   Reconnect one phone and one laptop; check lease, gateway and resolver.
6. `cloudflared` once percolator has something to publish (phase 5).

**Done when** a device that joins the Wi-Fi gets its lease and DNS from sieve,
Gatus is green for what exists, and an alert reaches the phone. **Way back:**
`./compose.sh pihole down` and turn the router's DHCP back on; clients fall
back within a lease renewal, sooner if reconnected.

## Phase 3: cellar, fleet management

1. Set cellar up with its 1 TB NVMe and second memory stick. `komodo`,
   `scrutiny`, `traefik`. Home Assistant is on cellar too (2026-11-22) but waits
   for phase 7: it signs in through Authelia, which comes in phase 5.
2. Copy Komodo Core's public key to sieve; bring up `komodo-periphery` and
   `scrutiny-collector` there. **Check** the merged collector: the node appears
   in Scrutiny under its name with its one disk.
3. Leave `smb` and `persian-perch` out (optional in `fleet.json`). Backups are
   the next phase.

**Done when** Komodo lists cellar and sieve, and Scrutiny shows both nodes'
disks. **Way back:** `./compose.sh --all down` on cellar; nothing depends on it yet.

## Phase 4: backups, on cellar

Before percolator (owner, 2026-11-21): no node holds household data until the
backups that would protect it run. At this point only sieve and cellar exist;
each later node joins the backups in its own phase (`backup.sh install`, its
key line on cellar, one `nightly` by hand) before any data goes on it.

1. **W2, written 2026-11-18.** The order to switch it on is in
   [stacks/backup/restic/README.md](../stacks/backup/restic/README.md), "Tying it
   together": `backup.sh install` on cellar and its secrets, then each node's
   `install` and its line in `restic/backup.keys`, then `repo-setup.sh` and
   `dump-store-setup.sh` on cellar.
2. Before that, on cellar: `findmnt /srv` and `df -h /srv` show the NVMe, and
   `sudo ../../stacks/backup/restic/repo-setup.sh --check` prints the keys it would install.
3. A new repository: `restic init` with a new password (every app starts
   empty, so nothing is restored). If the old Drive copy is still there, move
   it aside first: the drive-sync guard refuses to overwrite a different
   repository on Drive, by design. The password and the crypt keys go to the
   recovery kit the same day.
4. Per node (sieve and cellar now): `sudo ./backup.sh install`, `keys`, authorise the lines on cellar,
   `doctor`, then `nightly` by hand once, then `enable`.
5. A restore test of one node's snapshot into a scratch directory, and the
   Drive copy read back.
6. The offline copy: one HDD in the dock after each successful prune, the two
   alternating. Run a long SMART self-test on both first.
7. **W3, written 2026-11-18.** The recovery kit, from americano, the same day the
   new repository's keys exist: Ventoy on stick B, `recovery/make-flask.sh`, the
   vault with `fill-vault.sh`, the paper, one offline boot of each stick
   ([recovery-kit.md](recovery-kit.md), "Building it").

**Done when** two nights in a row sieve and cellar have a fresh snapshot, the morning
check is quiet, a restore test passed, and Drive holds the same repository.
**Way back:** `sudo ./backup.sh disable` per node; nothing else reads the repository.

## Phase 5: percolator, ingress and identity

Backups run from phase 4, so percolator joins them before its apps hold anything.

1. Set percolator up. Every app starts empty, so its data disk is wiped like
   the system disk; check first that the owner's backup of it is done.
2. `traefik-ingress`, `crowdsec`.
3. `mail-relay`, if the Purelymail app password exists (owner). Without it
   Vikunja and Vaultwarden will not start in phase 6, nor Paperless (on
   grinder) in phase 8.
4. `lldap`, then `stacks/identity/lldap/lldap-bootstrap.sh`; create the service
   accounts (`scottishfold`, `pixiebob`, `sphynx`, one LLM account per caller in
   `llm_api_group`). `authelia`.
5. On sieve: `./render-configs.sh` and recreate Pi-hole so the new names
   resolve; add cellar's and sieve's addresses to `FORWARD_AUTH_CLIENTS` if they
   changed; `sudo ./firewall.sh` on percolator.
6. `homepage`, then `komodo-periphery` and `scrutiny-collector`.
7. Backups: `sudo ./backup.sh install`, `keys`, its line in `restic/backup.keys`
   on cellar, `doctor`, `nightly` by hand once, `enable`.

**Done when** `authelia.${DOMAIN}` signs a person in, an admin page on sieve
and one on cellar ask for that sign-in and let an admin through, and a
household account is refused there. **Way back:** the other nodes' pages are
reachable on their own ports while Authelia is down, as designed.

## Phase 6: percolator, the household apps

One app at a time, in `node.conf` order: radicale, vaultwarden, mealie,
vikunja, meowgram, actualbudget, freshrss,
purrcafe. (On 2026-11-23 Immich, OpenCloud and Paperless moved to grinder,
phase 8. Karakeep, FitTrackee and Traccar came here from grinder that day and
left for mochaPot on 2026-11-24: optional there, set aside for now.)

Every app starts empty (owner, 2026-11-17). For each: bring it up, run its
README's checklist, add or confirm its Gatus check, and let one night's backup
pass before the household puts anything into the next one.

- OpenCloud and the other apps with upgrade gates record their version on a
  fresh install; nothing needs acknowledging.
- meowGram: an empty install of 2.0.0 needs no dump first.

**Done when** each app's checklist is ticked in the runbook with what was seen.
**Way back:** per app, `./compose.sh <app> down` and its data directory from
the night before.

## Phase 7: home (Home Assistant on cellar, then mochaPot)

Home Assistant moved from mochaPot to cellar on 2026-11-22
([hardware.md](hardware.md), "When a node goes down").

1. On cellar: `homeassistant`, onboarded fresh; the `configuration.yaml` steps
   in [its README](../stacks/home/homeassistant/README.md) (`trusted_proxies`
   is cellar's `proxy` subnet, `172.30.12.0/24`, and sieve's address; the
   recorder; sign-in through Authelia). `sudo ./firewall.sh` for port 8123.
   **Check** Bluetooth: `bluetoothctl list` on cellar. The ThinkCentres may have
   no Bluetooth; if so, a USB adapter or an ESPHome Bluetooth proxy, or none if
   nothing needs it. Then `esphome` (from grinder, 2026-11-23): its dashboard
   on `:6052` and Home Assistant's ESPHome integration find the first sensor.
2. On sieve: `./render-configs.sh`, recreate Pi-hole and cloudflared, so `homeassistant.${DOMAIN}` and
   `esphome.${DOMAIN}` point at cellar.
3. Set mochaPot up through its USB Ethernet adapter. `pihole-secondary` first;
   check it answers and that sieve's DHCP hands out both resolvers.
4. `musicassistant`, `traefik`. **Check** the merged Traefik with
   host-networked apps: Pi-hole's and Music Assistant's pages open through it.
5. `komodo-periphery`, `scrutiny-collector` (it uses
   `nodes/mochaPot/scrutiny-collector.yaml` for the SanDisk), the kiosk
   (`stacks/home/kiosk`, showing Home Assistant on cellar), backups.
6. Later, when the owner asks: the self-tracking apps, `karakeep`,
   `fittrackee`, `traccar` (optional on mochaPot since 2026-11-24). Their first
   visits are in mochaPot's README; the phone's Traccar server becomes
   `http://192.168.1.13:5055`. Watch the SanDisk: it's the smallest and least
   trusted disk in the fleet, and these are the apps that grow.

**Done when** `homeassistant.${DOMAIN}` signs in through Authelia and with the
local account, the kiosk shows the dashboard after a reboot of mochaPot, and
stopping sieve's Pi-hole for a minute leaves name resolution working.

## Phase 8: grinder, photos, files, documents, automation and AI

1. (owner) Choose the provider and model; make an API key for the fleet with
   a spending limit. Still open (2026-11-17): LiteLLM takes any endpoint that
   speaks the OpenAI API, so the choice is three settings when it's made.
2. Set grinder up. `postgres-vector`, `embedding-worker`, `n8n`.
3. `litellm` ([its README](../stacks/ai/litellm/README.md)): healthy, and
   `llm.${DOMAIN}` answers 401 to a request without credentials. Then
   `openwebui`: the model `default` is listed and answers.
4. `traefik` early this time (the next two have no direct port). Then
   `immich-ml` and `immich` (copy the mail relay's `ca.crt` from percolator
   first: [its README](../stacks/apps/immich/README.md)): its checklist;
   confirm 3003 is not reachable from another node; start Immich's jobs and
   watch grinder's load for a day. Then `opencloud`: its README's checklist,
   the CSP check from the Backlog. Then `paperless` (its `prepare.sh` builds the
   relay bundle from the copied `ca.crt`). One night's backup behind each
   before the household uses it.
5. The agents. Backups, as on every node.
6. `pourover`, last and only if wanted (`--include-optional pourover`): try
   its planning against the cloud model with one harmless message first.

**Done when** a chat in Open WebUI gets an answer, the provider's usage page
shows only that traffic, and new photos get faces. **Way back:** `litellm down`
costs nothing; the apps that call it queue or show an error.

## Phase 9: voice (W4)

Needs: phase 7 (Home Assistant on cellar), and the speaker and mic in each
room. Each ThinkCentre (sieve, percolator, cellar) runs Whisper, Piper and a
satellite (owner, 2026-11-17); Home Assistant on cellar decides what to do.
Written 2026-11-18 as `stacks/voice/`; the design and the steps are in
[voice.md](voice.md).

1. sieve (the living room) first: `host-setup.sh` for audio, then the three
   apps, then the Wyoming and ESPHome integrations and a room assistant in HA
   ([voice.md](voice.md), "Bringing up a room").
2. Measure: the speech-to-text time in HA's Assist debug view, written in the
   runbook. Over about two seconds, `tiny-int8` on that node.
3. Then percolator and cellar, the same way.

**Done when** each room answers its wake word from its own speaker, and the
speech-to-text times are in the runbook. **Way back:** `./compose.sh <app> down`
for the three apps; the integrations in HA can be deleted; `host-setup.sh` lists
what it changed on the machine.

## Phase 10: the ways in from outside

1. **W5**, the tailnet (written 2026-11-18): the policy pasted into the admin
   console and split DNS set ([tailscale/README.md](../tailscale/README.md)),
   then each node with the bootstrap one-liner and `--only tailnet`, americano
   and the phone. UFW stays the only gate, as before. The Remote Desktop grant
   is already out of `tailscale/policy.hujson`.
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
