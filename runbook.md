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

- [x] Do the ThinkCentres boot from the 128 GB M.2 SATA drives? No (owner, 2026-11-18). Disks re-planned: see the 2026-11-18 entry
- [x] A ThinkCentre boots from a 2.5" SATA SSD: yes (owner, 2026-11-18 23:22 IST)
- [x] The x360s' USB Ethernet adapters come up under Debian: yes (owner, 2026-11-18 23:22 IST). That the derived MAC sticks to them is checked in the rehearsal (payload's network step)
- [x] The x360s have two memory slots each, so grinder's 16 GB fits as two sticks (owner, 2026-11-18 23:23 IST)
- [x] The drives as planned in `docs/hardware.md` (owner, 2026-11-18 23:33 IST: "the count is okay as is for now"); not listed by label. If one turns out different at install, the table changes then
- [x] The router's address, and that its DHCP turns off: `192.168.1.1` (matches `GATEWAY` in stacks/fleet.env), and yes, it can be turned off (owner, 2026-11-18 23:23 IST). It stays on until sieve takes over in phase 2
- [x] The router's DHCP pool is `192.168.1.33`–`.249` (owner, 2026-11-18 23:40 IST): clear of the nodes' `.10`–`.14`, so sieve can take `.10` while the router still hands out leases
- [x] percolator and grinder surveyed (owner's script, 2026-11-23 entry): disks as installed, one stick in percolator so far
- [ ] purrbrews-bootstrap running on americano with americano's key in it (owner)
- [x] W1: the payload is written (`payload/`, 2026-11-18). Tests run four of its steps as root; none of it has run on a machine yet
- [x] Serve the payload from americano: purrbrews-bootstrap 1.1.0 in `~/Desktop/Tools/purrbrews-bootstrap`, the payload from a deployment checkout of main in `~/Desktop/Tools/purrbrews-containers`. `/files/SHA256SUMS` lists README.md, lib/fleet.sh and lib/net-apply.sh with main's hashes (owner's output, compared 2026-11-19 00:02 IST)
- [x] americano's address: set by hand on the Mac to `192.168.1.15`, outside the router's old pool (`.33`+) and Pi-hole's (`.50`+), so no DHCP server can hand it out; no reservation needed (owner, 2026-11-19 10:52 IST)
- [ ] Rehearse one fresh machine through the one-liner, twice. sieve holds nothing yet, so sieve is the rehearsal (owner, 2026-11-18). First run passed (owner's output, 2026-11-19 00:33 IST):
  - hostname `sieve`; `/opt/purrbrews/.env` has `NODE=sieve`, `NODE_IP=192.168.1.10`, `TZ=Asia/Kolkata`, `PUID`/`PGID` 1000;
  - `enp0s31f6` at `192.168.1.10/24` with the derived MAC `02:33:68:72:0b:17` (matches `scripts/fleet-macs.sh`), default route via `192.168.1.1`;
  - sshd: `passwordauthentication no`, `permitrootlogin no`, `allowusers barista`;
  - UFW active, 22/tcp from `192.168.1.0/24` only;
  - Docker 29.10.0 and Compose v5.8.0; barista not in the `docker` group, as designed (`sudo docker`);
  - `purrbrews-bootstrap-sync.timer` and `purrbrews-pull.timer` scheduled;
  - checkout at main, f9f144c.

  Still to see: the second run of the same command, changing nothing
- [ ] Close the open Dependabot PRs once this branch is merged; they target the old paths (owner)
- [x] First CI run on this layout: `tests` passed on PR #92's head c024bd3, including the root-only run (checked 2026-11-17 16:25 UTC)
- [x] OpenCloud to 9.1.1, the production line (owner asked, 2026-11-17; notes read, `docs/image-updates-2026-11.md`)
- [ ] n8n 3.x: only betas so far (2.48.4 is the newest stable); move once a stable 3.x is out, planned for early December. Check its SSRF list against tailnet addresses (`docs/image-updates-2026-11.md`)
- [ ] OpenCloud 9.1: check the custom CSP lets Excalidraw, Apollon and previews load (phase 8, on grinder)

**Phases 2 and 3: sieve, cellar** (phases renumbered 2026-11-22: backups are now 4, before percolator)

- [x] sieve: secrets set (`./setup-secrets.sh`: only `RESTIC_PASSWORD` left, for phase 5) and firewall applied: DNS 53 from the LAN, DHCP 67 from anywhere, the UIs from `proxy` only, voice from `192.168.1.13` only (owner's `ufw status`, 2026-11-19 00:51 IST)
- [x] sieve: Unbound and Pi-hole answer DNS with DNSSEC validation. From sieve: `debian.org` NOERROR; `dnssec-failed.org` SERVFAIL, and with `+cd` it resolves (96.99.227.255), so validation is what refuses it (owner's output, 2026-11-19 00:52 IST). From americano across the LAN, `debian.org` resolves the same (2026-11-19 00:53 IST)
- [x] sieve: DHCP handed over. The router's DHCP is off; Pi-hole's `dhcp.active` is `true`, it listens on `0.0.0.0:67`, range `192.168.1.50`–`.250`, router `192.168.1.1` (owner's output, 2026-11-19 10:51 IST); devices get their leases from it (owner, 10:58 IST). `enable-dhcp.sh` itself failed on `KeyError: 'LAN_CIDR'` before changing anything; fixed (it now reads fleet.env), with a test. Pi-hole had in fact served DHCP since its first start the night before, beside the router's: its compose always enables it, and the plan wrongly said "DNS only" (corrected)
- [x] sieve: a test alert reached the phone (Android, the ntfy app on `https://ntfy.<domain>` as barista, topic `purrbrews-alerts`; owner, 2026-11-19 12:07 IST). Getting there:
  - Pi-hole answered app names with Cloudflare's addresses until it was recreated (`./compose.sh pihole up -d`); after that `dig @127.0.0.1 ntfy.<domain>` gave `192.168.1.10` (11:19 IST). Why the first start lacked them isn't known; Gatus's "pihole local override" check will catch a repeat once Gatus runs;
  - the phone's Android **Private DNS** sent lookups past Pi-hole; turned off (owner). The router's IPv6 DHCP and DNS are off too (owner). The Mac had `1.1.1.1` as its second DNS server; to be replaced with `192.168.1.13`. Notes in `stacks/network/pihole/README.md`, "Handing over DHCP"
- [x] IPv6 on Tata fiber (new since ACT's IPv4-only CGNAT): sieve has no global IPv6 address (`ip -6 addr show scope global` empty, owner's output 2026-11-19 12:11 IST), as the payload intends (`ipv6.method disabled`), so its `[::]` listeners (22, 53, 80, 443) are unreachable over IPv6. The router's IPv6 DHCP and DNS are off (owner). Still worth a look: the Humax's IPv6 firewall blocks inbound, for the household's own devices (owner)
- [ ] sieve: Gatus running with the `GATUS_WATCH_*` switches off (after `git pull` and `./setup-secrets.sh`), its log clean, and its "pihole local override" check green
- [x] cellar set up (owner's output, 2026-11-23 19:48–20:27 IST): ThinkCentre M710q, i3-7100T with AVX, 16 GB (2 × 8 GB Hynix, 2400 MT/s), UEFI. Debian 13 went onto a 256 GB SATA SSD in the 2.5" bay (the planned spare) rather than the NVMe; kept, with the whole 1 TB NVMe as `/srv` (ext4, label `srv`, in fstab; 938 GB). NVMe SMART passed, 0% used. Intel Bluetooth present (for Home Assistant). The onboard NIC reports the placeholder MAC `88:88:88:88:87:88`; the payload's own MAC covers it. After the one-liner: hostname `cellar`, `192.168.1.12`, checkout in place (20:27 IST)
- [x] cellar: `sudo` said "unable to resolve host cellar": 127.0.1.1 still named the install-time `debian`. Fixed by hand; the payload now rewrites that line (commit, 2026-11-23)
- [x] cellar: Komodo up (Core v2.3.4, admin `barista` created, serving on 9120; 20:39 IST); Scrutiny watching both disks (`DISK_DEVICE=/dev/nvme0`, `DISK_DEVICE_2=/dev/sda`; owner, 20:46 IST); Traefik up, no errors in its log, `acme.json` written (28 KB; 20:50 IST)
- [x] sieve's agents registered with cellar: `komodo-periphery` (with cellar's `core.pub`) connected in Komodo; `scrutiny-collector` showing sieve's SSD after a run by hand (owner, 2026-11-23 21:00 IST). Phase 3 done
- [ ] sieve: `sudo ./firewall.sh` again for the voice rules from cellar (`192.168.1.12`), then delete the three from `192.168.1.13` (`sudo ufw status numbered`, `sudo ufw delete <n>`): Home Assistant moved (2026-11-22 entry)

**Phase 4: backups**

- [x] W2: the repository's SFTP account on cellar (`restic/repo-setup.sh`); hub scripts and README without roastery; tests extended. Written and run against a real sshd in the sandbox (2026-11-18 entry); not yet on cellar
- [x] The repository account's name: `burmilla` (owner, 2026-11-18); in `BACKUP_REPOSITORY`, `stacks/fleet.env`
- [x] On cellar before phase 4: `/srv` on the NVMe (`findmnt /srv`: `/dev/nvme0n1p1`, 938 GB; owner's output, 2026-11-23 21:18 IST), then `repo-setup.sh --check` (the 21:28 line below)
- [x] A new repository: repository `076d6cf0` opens (restic version 2), snapshots in it from 2026-11-23 21:41 IST
- [x] Restic password and the two crypt values copied off the fleet (owner, 2026-11-24 22:10 IST: "done"; where not recorded here). Not in Vaultwarden, by design (its data is inside the repository)
- [ ] The same three into the recovery kit's vault (`fill-vault.sh` on americano), when the sticks are ready
- [x] cellar: `backup.sh install`, secrets generated, `repo-setup.sh --check` showed `burmilla` chrooted to `/srv/backup` with cellar's key (2026-11-23 21:28 IST); repository opened, and cellar's first files snapshot saved (`89716cdf`, 21:41 IST)
- [x] cellar's first `enable` stopped on "dump failed" (persianPerch's optional SQLite not there), and sieve's doctor failed on NetAlertX (never started). Fixed in #112 (apps never started are left out with a note). After the pull both `enable`s passed (owner's output, 2026-11-23 22:00 IST): cellar doctor "All good", Komodo dump, snapshot `7a6a674b`, all six hub timers on; sieve doctor "All good", Pi-hole and ntfy dumps, snapshot `60363a10`, timer on. Left out as not started: homeassistant, smb, persian-perch (cellar); cloudflared, netalertx (sieve)
- [x] sieve's dumps did **not** reach cellar at first: rsync said "Unable to create partial-dir … discarding completed file" for both, exited 0, and the night said OK. Confirmed on cellar (owner's output, 22:18 IST): rsync 3.5.0; `/srv/dumps/sieve` holds empty `ntfy/` and `pihole/` and a stray `.rsync-partial/`, no files. The cause in rsync itself isn't pinned down; the two options are what the push no longer uses, and `--delete` clears the stray folder on the next push. The push now drops both options and fails on anything rsync says on stderr (branch `backup-push-fix`, test with rrsync); then `sudo ./backup.sh push` on sieve and check the files on cellar Fixed in #113 (merged 2026-11-23 22:19 IST); after it, cellar's `/srv/dumps/sieve` holds `pihole/gravity.sql.gz` (575 KB) and `ntfy/users.sql.gz`, and the stray `.rsync-partial/` is gone (owner's listing, 22:20 IST)
- [x] First night clean (`check-freshness.sh` on cellar, owner's output, 2026-11-24 19:09 IST): cellar and sieve files and dumps ok (16–17 h), every timer fired; STALE only for the three nodes not built and for Drive (not set up then). The STALE alerts for nodes not yet built stay (owner: not worth changing)
- [x] A second clean night (`check-freshness.sh` on cellar, owner's output, 2026-11-25 08:03 IST): cellar, sieve **and percolator** (its first night) files and dumps ok (5–6 h), Drive ok (4 h); STALE only grinder and mochaPot, not built. Phase 4 done but for the recovery kit's vault and the HDDs' SMART tests
- [x] sieve and cellar: install, keys, doctor, one nightly by hand, enable (the 2026-11-23 22:00 line above); every later node the same in its own phase
- [x] Google Drive copy: own OAuth client, `drive-setup.sh`, first `drive-sync` by hand (owner, 2026-11-24 21:57 IST: "done"; no output seen by Claude)
- [x] Restore test passed from the repository and from Drive, `--host sieve` (owner, 2026-11-24 22:06 IST: "Restore test passed (repo)", "Restore test passed (drive)")
- [ ] Long SMART self-test on both old HDDs before they hold the offline copies
- [x] W3: the recovery kit rebuilt from americano (`recovery/`, docs/recovery-kit.md). Written; a full download-and-verify and a build onto two stand-in sticks passed in the sandbox (2026-11-18 entry). Not yet on a real stick or a Mac
- [ ] flask, the owner's part, once the new repository's keys exist: Ventoy on stick B (from Linux), `./make-flask.sh` on americano with both sticks, the vault (`fill-vault.sh`), the paper, then one boot of each stick on a ThinkCentre with the cable out (owner)
- [ ] First run of `make-flask.sh` and `fill-vault.sh` on americano itself: they were written for macOS's bash 3.2 and tested only on Linux's bash 5 (sandbox, 2026-11-18). A `--prepare` on the Mac settles it

**Phase 5: percolator, ingress and identity**

- [x] percolator set up by the payload: hostname `percolator`, `192.168.1.11`, 7.7 GiB (one stick), `127.0.1.1 percolator` written by the payload's new hosts step (owner's output, 2026-11-24 22:29 IST). `setup-secrets.sh` done; only `RADICALE_LDAP_READER_PASSWORD` left (needs `scottishfold`)
- [ ] percolator's second RAM stick (ChannelB empty)
- [ ] The Seagate HDD out of percolator's bay (owner, later: "leave it for now"); it's one of the two offline copies. Long SMART test when it's out
- [x] CrowdSec with the Traefik bouncer registered (`cscli bouncers list`: `traefik`, valid, pulling; owner's output, 2026-11-24 23:04 IST); traefik-ingress with no errors in its log and `/srv/data/traefik/letsencrypt/acme.json` written (16 KB, 23:02 IST)
- [x] Purelymail app password in place (owner); mail relay up (Postfix 3.11.7, opendkim, rspamd running, 23:05 IST) and a test message from `purrBrews@` received (owner, 23:14 IST)
- [x] LLDAP up (v0.6.3; admin and `lldap_strict_readonly` created on first start); `lldap-bootstrap.sh` created `purrbrews_admins`, `purrbrews_household` and `barista` in both (owner's output, 23:14 IST). It had to be run with `bash`: committed without the executable bit (fixed on branch `runbook-dumps-landed`, with a test). `https://lldap.${DOMAIN}` signs in (owner, 23:31 IST)
- [ ] `barista`'s email in LLDAP: set to `barista@${DOMAIN}` by the bootstrap; change it if that mailbox doesn't exist (Authelia's resets go there) (owner)
- [ ] **Open bug:** signing in to `https://komodo.${DOMAIN}` (cellar) through Authelia doesn't work (owner, 2026-11-24 23:31 IST): the browser gets Komodo's own login page, so cellar's Traefik isn't applying the Authelia middleware to that route at all (no redirect). Parked until every container is up (owner, 23:40 IST: failures go here and are tackled then). Not looked into: Authelia's log, whether the redirect to `authelia.${DOMAIN}` happens, cellar's `FORWARD_AUTH_CLIENTS` and Traefik middleware, and whether sieve's Pi-hole was re-rendered for the new names are the first things to check
- [ ] Service accounts: `scottishfold` (Radicale's reader, `lldap_strict_readonly` only) before Radicale; `pixiebob`, `sphynx` and the `llm_api_group` accounts with their apps
- [x] percolator's backups on: `install`, its key line in cellar's `backup.keys`, `repo-setup.sh` and `dump-store-setup.sh` on cellar, `enable` (owner, 2026-11-24 23:39 IST); its first night's files and dumps ok in `check-freshness.sh` (2026-11-25 08:03 IST)
- [x] percolator's `komodo-periphery` and `scrutiny-collector` up, added in Komodo (owner, 23:39 IST: "done")
- [ ] percolator: `homepage`

**Phases 6 to 8: the apps**

- [x] percolator's household apps up together, empty (owner chose all at once over one a night: they hold nothing yet): radicale, vaultwarden, mealie, vikunja, meowgram, actualbudget, freshrss, purrcafe all `up`, no container restarting or unhealthy; 2.0 GiB used of 7.7, no swap in use, 9.3 GB of 225 GB on `/` (owner's output, 2026-11-25 08:09 IST)
- [x] Each household app's first visit (owner, 2026-11-25 10:11 IST): all eight up and loading
- [ ] **Open:** Radicale doesn't go through Authelia and asks for a username and password (owner, 2026-11-25). Likely by design: its README says ForwardAuth would break DAV clients (phones), so it checks LLDAP itself with basic auth, through `scottishfold`. But `barista` with its LLDAP password **also fails** (owner, 2026-11-25 10:19 IST), so this is a real bug. First checks: `./compose.sh radicale logs` for LDAP bind or search errors; that `scottishfold`'s password in `apps/radicale/secrets.env.local` matches LLDAP and `render-configs.sh` was re-run after it; that `barista` is in `${LLDAP_HOUSEHOLD_GROUP}`
- [ ] **Open:** purrCafe shows nothing connected (owner, 2026-11-25). Its panels need their sources: a Home Assistant token (cellar, phase 7), Actual's Sync ID and token, a Gatus token, and each person's mailbox in its Settings (stacks/apps/purrcafe/README.md); then `./setup-secrets.sh` on percolator for the tokens
- [x] cellar: Home Assistant 2026.11.2 and its Postgres 16.16 up (postgres healthy; owner's output, 2026-11-25 10:18 IST)
- [ ] **Open:** Home Assistant's Bluetooth: `habluetooth` "Failed to force stop scanner" on `hci0`, and `bluetoothctl` isn't on cellar: the host has no BlueZ, which HA reaches over `/run/dbus`. Fix: `sudo apt install bluez`, `sudo systemctl enable --now bluetooth`, restart HA. If it fixes it, the payload should install `bluez` on Home Assistant's node (proposal)
- [x] cellar: Home Assistant onboarded (local owner account), `trusted_proxies` = cellar's `proxy` subnet `172.30.12.0/24` and sieve `192.168.1.10/32`; `https://homeassistant.${DOMAIN}` resolves and loads, and signing in through Authelia works (HACS, hass-oidc-auth set up through HA's UI, not `configuration.yaml`, so its settings live in `/srv/data/homeassistant/.storage`, backed up with the rest) (owner, 2026-11-25 10:35 IST)
- [ ] Home Assistant's recorder on Postgres (`configuration.yaml`, its README); not confirmed, SQLite until then
- [ ] cellar: ESPHome beside it, its first sensor found by Home Assistant
- [ ] mochaPot: secondary Pi-hole, Music Assistant, the merged Traefik checked with host-networked apps, the kiosk showing Home Assistant on cellar
- [x] grinder set up by the payload; `setup-secrets.sh` with the LLM provider, pourOver's account and Vikunja ids left blank (undecided). traefik, postgres-vector, embedding-worker, n8n, litellm, openwebui, immich-ml, immich, opencloud up on the first pass; paperless refused (no relay bundle): the relay's `ca.crt` had never arrived, because grinder can't SSH to percolator (only americano's key is on the nodes) and `install` needed the folder first. Copied through americano; then paperless, its Postgres and Valkey healthy, and Immich recreated, all healthy; `bundle.crt` built. 6.0 GiB used of 15, 23 GB of 922 GB (owner's output, 2026-11-25 22:59–23:08 IST). The relay and Immich READMEs now copy through americano
- [x] grinder's backups on (`enable`: doctor passed, first nightly OK, snapshot `46c0aa8b`, 133 files; timer on at 01:34) and its `komodo-periphery` and `scrutiny-collector` up (owner's output, 2026-11-25 23:17 IST)
- [x] Immich: admin account, OAuth set up in its UI (issuer `https://authelia.${DOMAIN}`, client `immich`, `client_secret_basic`); *Login with Authelia* first failed with "Error in OAuth discovery: TypeError: fetch failed", then works (owner, 2026-11-25 23:48 IST: "fixed"; cause and fix not recorded yet)
- [ ] **Open (design bug):** the OIDC client secrets of apps on grinder (Immich, Paperless; OpenCloud to check) are generated twice: percolator's `setup-secrets.sh` makes one to hash for Authelia, grinder's makes its own for the app, so they differ. For now the app takes percolator's value by hand (Immich in its UI; Paperless by editing grinder's `paperless/secrets.env.local` and recreating). Fix: keep cross-node clients' plaintext beside Authelia, as Home Assistant's already is (`authelia/secrets.conf`), and have the apps' READMEs copy it from there; correct Immich's README, which points at grinder's copy
- [ ] Pi-hole's admin page at `pihole.${DOMAIN}/admin/` answered with Pi-hole's own 403 "Access denied" (owner, 2026-11-26 13:50 IST): through Authelia and Traefik fine, but Pi-hole v6 only serves its UI for its own name. Fix: `FTLCONF_webserver_domain: pihole.${DOMAIN}` (this commit); on sieve after the pull, `./compose.sh pihole up -d --force-recreate` and reload. Not yet confirmed
- [ ] grinder: LiteLLM healthy and `llm.${DOMAIN}` refusing a request without credentials; Open WebUI answering; Immich up with its ML, port 3003 unreachable from other nodes; OpenCloud and Paperless signing in through Authelia; Paperless's test mail arrives (the bundle built from the copied `ca.crt`)
- [ ] pourOver's planning tried against the cloud model before it is switched on
- [ ] CrowdSec or not in front of Immich, OpenCloud and Paperless on grinder, before their tunnel routes go live (owner)
- [ ] A second disk in mochaPot for the growing data (Karakeep, Traccar, FitTrackee) (owner, 2026-11-24): one of the two Seagate 1 TB HDDs, if it passes the long SMART test. Check first that the x360 laptop has a 2.5" bay (the board does). That leaves one HDD for the offline copies, so no turn-taking: decide how the offline copy works with one disk. Then mount it (for example `/srv/bulk`) and point the three apps' data folders at it
- [ ] Traccar: the phone's server changed to mochaPot, `http://192.168.1.13:5055` (owner, when Traccar comes up; it moved there 2026-11-24)

**Phases 9 to 11**

- [x] W4: voice written (`stacks/voice/`, docs/voice.md; 2026-11-18 entry). Compose files render and the firewall lets in mochaPot alone (tests); not run on a machine
- [ ] Voice, phase 9: sieve's room end to end (`host-setup.sh`, the three apps, the HA integrations and the room's assistant), the speech-to-text times written here, then percolator and cellar (owner)
- [x] W5: the payload's `tailnet` step, and the Remote Desktop grant out of `tailscale/policy.hujson` (2026-11-18 entry). Tested against stand-in commands; not run on a machine
- [ ] Tailnet, phase 10: the policy pasted and split DNS set in the admin console, then each node `--only tailnet`, americano and the phone; the checks in tailscale/README.md, "Is it working?" (owner)
- [ ] Cloudflare tunnel routes in one pass; then the visitor-address check
- [ ] Two-factor in Authelia once every account has enrolled
- [ ] W6: node READMEs rewritten; roastery wording swept from app READMEs and comments
- [ ] Carried from the old Backlog, still open: `barista` in the `docker` group; Samba, shares or gone; a bot identity for agents' commits; the merged branches on GitHub (owner)

## 2026-11-24 — Karakeep, FitTrackee and Traccar to mochaPot, set aside for now

**What.** The owner was worried about percolator's memory (one 8 GB stick so
far) and its 256 GB disk, and asked for apps to move. Claude advised against
moving most of the household apps to grinder (already the fuller box in
memory, and on USB Ethernet), against Home Assistant on percolator (one
failure would take sign-in and the house together), and for moving only what
is heavy and grows. The owner decided: **Karakeep, FitTrackee and Traccar go
to mochaPot, optional, and are set aside for now** (2026-11-24 23:52 IST).
Everything else stays: the household apps on percolator, Home Assistant and
ESPHome on cellar.

**Changed** (branch `self-tracking-to-mochapot`):

- The three out of percolator's `node.conf`, into mochaPot's after Music
  Assistant, and optional in `fleet.json` (so `--all` skips them); Karakeep's
  Meilisearch prerequisite moves with it.
- Their routers use `authelia-forwardauth@file` (the shared Traefik's
  ForwardAuth to percolator), as they did on grinder. **Caveat:** that is the
  same cross-node ForwardAuth that doesn't redirect for Komodo on cellar
  (Backlog), so check it there first.
- Tunnel routes and Gatus checks to mochaPot; DNS and firewall tests follow.
- READMEs (percolator's and mochaPot's: apps, ports, data, first visits), the
  hardware doc (rows, why, failure and memory tables), MAP, carry-over map,
  migration plan (phase 7, step 6), image upgrades.

**Way back:** the commit reverts cleanly; nothing ran on a machine. If the
loop on percolator already started any of the three, `./compose.sh <app> down`
there; their data folders are empty.

## 2026-11-23 — percolator and grinder surveyed; disks as installed; grinder takes the growing data

**What.** The owner ran a hardware survey on two machines (pasted in chat,
2026-11-23 IST) and decided, in chat at 22:11 and 22:13 IST:

- The ThinkCentre M710q now at `192.168.1.163` (DHCP) is **percolator**; the
  HP x360 at `192.168.1.119` (USB adapter, no Wi-Fi: the board) is **grinder**.
- **The disks stay as installed**, which swaps the 2026-11-22 plan's two:
  percolator boots from the 256 GB EVM NVMe (cellar's old system disk),
  grinder from a 1 TB WD SN530 NVMe. The old Seagate ST1000LM035 is in
  percolator's 2.5" bay for now, holding an installer image.
- **Immich moves from percolator to grinder**, onto the big disk and beside
  its machine learning.
- **OpenCloud follows it** (owner, 22:31 IST), for the same disk: with both on
  grinder, percolator's 256 GB holds only small, slow-growing data.
- **Paperless too, and grinder's self-tracking and house apps leave**
  (owner, 22:49 IST; Claude proposed the split by role and the owner chose
  it): Karakeep, FitTrackee and Traccar to percolator (behind sign-in, like
  the rest there), ESPHome to cellar beside Home Assistant, Speedtest Tracker
  to sieve (it measures the line; small, nothing depends on it).

The owner had also weighed percolator on the x360; Claude advised against it
(same CPU class, all ingress through a USB adapter, the voice rooms) and the
owner kept percolator on the ThinkCentre.

**What the surveys showed** (`docs/hardware.md`, "Checked on the machines"):
both UEFI, Debian 13, kernel 6.12.117, AVX, SSH up with password login still
on, clocks synced. The M710q has one 8 GB stick (ChannelB empty) and Intel
Bluetooth. The x360 has a mixed pair (SK Hynix + G.Skill 3200, both at 2133).

**Changed** (`claude/immich-to-grinder`):

- `immich` and `opencloud` out of percolator's `node.conf`, into grinder's
  after `immich-ml`. OpenCloud keeps `OC_OIDC_ISSUER` on Authelia, now
  reached through Pi-hole's record; its router names the `cloudflare`
  resolver; its upgrade-gate prerequisite moves to grinder in `fleet.json`.
- Immich reaches its ML as `immich-machine-learning:3003` on grinder's `proxy`
  network; `IMMICH_ML_URL` is gone. immich-ml publishes no port and its
  `firewall` file is removed.
- Mail: percolator's relay at `192.168.1.11:587` (grinder is already in
  `MAIL_RELAY_CLIENTS`; the certificate carries that address), with a copy of
  the relay's `ca.crt` on grinder (Immich README).
- The shared `stacks/network/traefik` (grinder, cellar, mochaPot) gets
  `readTimeout: 0s`, as traefik-ingress has, so long uploads aren't cut at
  60 s; Immich's router names the `cloudflare` resolver.
- The tunnel route and the Gatus check point at grinder; Pi-hole's record
  follows on the next render on sieve and mochaPot.
- `docs/hardware.md` (both rows, the failure and memory tables, disks), the
  migration plan (both apps in phase 8, grinder's Traefik first), READMEs,
  MAP, carry-over map, `docs/image-upgrades.md` and `docs/recovery-kit.md`
  (OpenCloud's gate and secrets are on grinder).
- grinder's `local.env.example` gains `LLDAP_ADMIN_GROUP` and
  `LLDAP_HOUSEHOLD_GROUP` (same names as percolator's) for OpenCloud's roles.
- Paperless: out of percolator, into grinder after OpenCloud; mail to
  `${PERCOLATOR_LAN_IP}` instead of `mail-relay`; its router names the
  resolver; `PAPERLESS_OCR_LANGUAGE` moves to grinder's env example.
  `mail-relay/require-bundle.sh` now builds `bundle.crt` itself on a node with
  a copied `ca.crt` and no relay (before, only the relay's own `prepare.sh`
  made it, on percolator), so Paperless's `SSL_CERT_FILE` (mail and its OIDC
  login) works on grinder. The relay README says how to copy the CA.
- Karakeep, FitTrackee, Traccar: into percolator's `node.conf` after FreshRSS;
  their ForwardAuth label is `authelia@file` (percolator's middleware name,
  not the shared Traefik's `authelia-forwardauth@file`). Tunnel routes and
  Gatus checks to percolator; Karakeep's Meilisearch gate in `fleet.json` too.
  Ports 3030, 5001, 8082 and Traccar's 5055 are now percolator's.
- ESPHome: into cellar's `node.conf` after Home Assistant; host-networked
  there too, its firewall unchanged; Gatus under cellar.
- Speedtest Tracker: into sieve's `node.conf`. traefik-edge has no Docker
  provider, so its route moved from labels to `traefik-edge/dynamic/sieve.yml`;
  persianPerch reads it at `${SIEVE_LAN_IP}:8765`; Gatus under sieve.
- Node READMEs (grinder, percolator, cellar, sieve), hardware, MAP, README,
  migration plan, carry-over map, recovery kit, image upgrades.
- Tests: the backup test finds Immich in grinder's plan; the DNS test sends
  `opencloud`, `immich` and `paperless` to `.14`, `karakeep` to `.11`,
  `esphome` to `.12`, `speedtest` to `.10`; the host-networked firewall test
  checks ESPHome on cellar and FitTrackee's route rule on percolator; a new
  test builds the bundle from a copied CA and picks up a replaced one.

**Open**

- percolator's second stick (16 GB planned; one in).
- No CrowdSec in front of Immich, OpenCloud or Paperless on grinder (Backlog).
- Traccar's phone setting points at the old address (Backlog).
- The Seagate: still meant for the offline copies; long SMART test and wipe.

**Undo.** Revert the branch's commits: every app returns to where the
2026-11-22 plan had it, Immich with `IMMICH_ML_URL=http://192.168.1.14:3003` and
immich-ml's firewall file.

## 2026-11-22 — Layout by failure: Home Assistant to cellar; disks recounted; backups before percolator

**What.** The owner recounted the disks and asked Claude to decide the split of
apps across the machines by function and by what each failure takes down,
memory included. Decided (Claude, at the owner's request):

- **Machines as planned.** percolator stays on its ThinkCentre (ingress and
  sign-in on built-in Ethernet); grinder stays on the x360 board.
- **Home Assistant moves from mochaPot to cellar.** Built-in Ethernet instead of
  a USB adapter; not percolator, so the house keeps working when sign-in is
  down; cellar is the quietest node. The cost: cellar now carries Home
  Assistant and backups together. Music Assistant stays on mochaPot (owner).
  The kiosk shows Home Assistant on cellar at `http://192.168.1.12:8123`.
- **Disks** (owner's count: two 1 TB, one 512 GB and one 256 GB NVMe, two
  256 GB SATA SSDs, two 128 GB M.2 SATA, plus roastery's own 1 TB): grinder on
  the 256 GB NVMe (the old plan's "512 GB Intel NVMe" for grinder was wrong);
  the 512 GB NVMe kept for roastery (owner); spares are a 256 GB SATA SSD
  (sieve's kind) and a 128 GB M.2 SATA (mochaPot's kind). No spare for the 1 TB
  drives.
- **Memory unchanged:** 8 / 16 / 16 / 8 / 16 GB.
- **Backups before percolator** (owner, 2026-11-21): the migration plan's
  phases 4 and 5 swapped. Backups are phase 4, with only sieve and cellar;
  each later node joins in its own phase.

The table of what each failure stops, and the memory estimates, are in
`docs/hardware.md`, "When a node goes down".

**Changed.** `nodes/cellar/node.conf` and `nodes/mochaPot/node.conf` (APPS);
the voice firewalls (`$CELLAR_LAN_IP`); cloudflared's route for
`homeassistant`; the Gatus check (now under cellar's switch); purrCafe's and
persianPerch's Home Assistant URL; the kiosk's `KIOSK_URL`; the HA README's
`trusted_proxies`; tests; `docs/hardware.md`, `migration-plan.md`, `voice.md`,
`MAP.md`, `carry-over-map.md`, the node READMEs, `fleet.json`. Pi-hole's record
for `homeassistant` follows from `node.conf` (`refresh-dns`).

**Not done.** Nothing on a machine. sieve's firewall still has the three voice
rules from mochaPot (applied 2026-11-19); re-run and delete, as in the backlog.

## 2026-11-18 — W4 and W5: voice in each room; the tailnet step

**What.** The owner asked to finish W4 and W5. Both are written; neither has
run on a machine. Also fixed steps 4 and 5 of phase 1 in the migration plan,
which an earlier edit had run together.

**W4, voice** (`stacks/voice/`, [docs/voice.md](docs/voice.md)). Each
ThinkCentre (sieve, percolator, cellar) runs three apps:

- `whisper`: speech to text, `rhasspy/wyoming-whisper` 3.8.1.
- `piper`: text to speech, `rhasspy/wyoming-piper` 2.5.3.
- `voice-satellite`: Linux Voice Assistant 1.1.18, which handles the wake
  word, the mic and the speaker.

Home Assistant on mochaPot is the only client.

Decisions (Claude's, open to change):

- **Satellite: Linux Voice Assistant**, not Wyoming Satellite. Wyoming Satellite
  is no longer maintained, and Linux Voice Assistant replaced it. It speaks the
  ESPHome protocol and has the wake word built in, so there's no openWakeWord
  service.
- **Audio through the ops user's PipeWire**, over its PulseAudio socket, which
  is how the image expects it. `host-setup.sh` installs PipeWire and sets it up
  for a headless node:
  - lingering, so it runs with nobody logged in;
  - a WirePlumber setting so it doesn't wait for a logged-in seat.

  `prepare.sh` won't start the satellite without the socket.
- **Only mochaPot is let in.** Neither protocol authenticates, so each app's
  firewall file allows mochaPot alone: 10300 and 10200, plus 6053 and mDNS for
  the satellite. The satellite's peripheral API, which listens everywhere by
  default, is switched off.
- **Whisper model `base-int8` to start** (`VOICE_WHISPER_MODEL`, fleet.env).
  Not measured: the first room settles it. percolator's
  `local.env.example` has the `tiny-int8` line ready.
- **Images one release back:** Whisper 3.9.0 and Piper 2.5.4 both came out on
  2026-11-17.

**W5, the tailnet.** The old init's tailscale step is now the payload's
`tailnet` step (`payload/purrbrews-node.sh`). It runs only when named:

```
… bash -s -- --user barista -- <node> --only tailnet
```

It refuses to run together with `network`. Settings are in
`payload/payload.env`. It does the same as the old step:

- `--netfilter-mode=off`, so UFW is the only gate: 22 on `tailscale0`, and
  41641/udp.
- On cellar and grinder, the subnet routers: forwarding, the UFW route rules
  for 443 and 53, and the NAT unit.
- An auth key by file only, deleted once used.

**Fixed along the way:**

- The route was `192.168.1.0/23`, which is not a network (a /23 starts on an
  even third number). An earlier address sweep had turned the old
  `192.168.0.0/23` into it, in both the policy and the README, and Tailscale
  would have refused it. It's `192.168.0.0/23` again, which holds the house's
  `192.168.1.0/24`. A test now checks the route against `LAN_CIDR` and the
  policy's auto-approver.
- The Remote Desktop grant (for roastery) is out of `tailscale/policy.hujson`.
  `tailscale/README.md` is rewritten without roastery or the old init.

**Evidence** (sandbox, 2026-11-18):

- **Voice:**
  - `docker compose config` renders all three apps with sample settings,
    including the room-name default.
  - Digests were read from Docker Hub's tags API (its registry endpoint refused
    this sandbox) and from GHCR.
  - The images themselves weren't run: there's no Docker daemon here.
- **Tests:** 113 passed as root, 116 as an unprivileged user. New ones:
  - voice on exactly the three ThinkCentres;
  - its firewall rules from mochaPot only, on each;
  - the tailnet step only when named;
  - the route and the policy agree;
  - the step run as root against stand-in `tailscale`/`ufw`/system commands.
    A router gets the NAT unit, forwarding and `--advertise-routes`, and the
    key is passed as `file:` and deleted. A plain node gets none of that.
    With no key and no terminal it doesn't run `up`.
- shellcheck is clean.

**Not checked:** `host-setup.sh` (it needs systemd user sessions; none here),
the real images and devices, and a real `tailscale up`. These are phases 9 and
10, in the Backlog.

**Undo:** revert the commits. Nothing outside the repo changed.

**Next:** W6, the node READMEs, as each node comes up. Everything else is the
owner's phases.

## 2026-11-18 — W3: the recovery kit, built from americano

**What.** The owner said "next?" after W2 merged. W3 was next in
[the plan](docs/migration-plan.md): flask, the offline recovery kit, was built by
PowerShell on roastery, which is gone. It's now `recovery/`, in bash, for
americano. What goes on the sticks and in the vault is unchanged in kind.
Nothing ran on a node or on a stick.

**What's new:**

- `recovery/make-flask.sh`, ported from `make-flask.ps1`. It has the same
  steps (download, verify against the pinned keys, stage, write, read back) and
  the same `--prepare` and `--check` modes. It finds sticks with `diskutil` on
  macOS and `lsblk` on Linux. It keeps macOS's leftovers (`._` files, Spotlight)
  off the sticks and out of the checks, and packs the boot-time archive as root
  whoever builds it.
- `recovery/fill-vault.sh`, ported from `fill-vault.ps1`. It reads over SSH, and
  values go to `keepassxc-cli` on stdin only.
- `recovery/vault.tiers`: the vault list in one place, which the script reads
  and two tests check against the doc and against the apps' `secrets*.conf`.
- `recovery/RECOVERY.md`, rewritten for this fleet. Case B is now "cellar is
  gone".
- `docs/recovery-kit.md`, which replaces `docs/flask.md`.
- `recovery/live/` came over unchanged apart from comments.

**Decisions** (Claude's, open to change):

- **The name stays flask**, and so do the labels FLASK-A and FLASK-B: stick A
  already has Ventoy and that label (2026-09-30).
- **Ventoy is installed from Linux**, because there's no macOS installer: a
  node, or stick A booted on a ThinkCentre. Commands in the doc.
- **Mac tools added:** restic, rclone and the KeePassXC `.dmg` for both Mac
  architectures, because americano is now where the kit gets used.
- **Versions:** restic 0.19.1, rclone 1.76.0 (6 November, a security release),
  Debian Live 13.7.0. KeePassXC stays on **2.7.12** even though 2.8.0 came out
  on 4 November: 2.7's AppImage is the one proven in the live system. Try 2.8 at
  the yearly check, with a boot.
- **Vault list brought up to date:**
  - Added `CAFE_APP_ENCRYPTION_KEY` and `CAFE_ACTUAL_ENCRYPTION_PASSWORD`
    (Tier 2), `MAIL_RELAY_PASSWORD` and `LLM_UPSTREAM_API_KEY` (Tier 4).
  - Dropped `OPENCLOUD_THUMBNAILS_TRANSFER_TOKEN` (gone in OpenCloud 9.1) and
    roastery's Windows password.
  - `PIHOLE_WEBPASSWORD` is only the secondary's; the primary has none.
- **Boot test on a ThinkCentre with the cable out**, not in a VM: Apple Silicon
  can't boot x86, and a VM doesn't test the firmware anyway.

**Evidence** (sandbox, 2026-11-18):

- `./make-flask.sh --prepare` for real, against the live sites:
  - All four pinned keys imported with matching fingerprints.
  - Signatures were good on Debian's SHA512SUMS, restic's and rclone's
    SHA256SUMS, and all four KeePassXC files.
  - Every download matched its signed checksum, and LiveInjection matched its
    pinned hash.
- Written onto two stand-in sticks (folders): 146 files each read back against
  `SHA256SUMS`, and `sha256sum -c` agrees. The restic and rclone binaries from
  the stick run (`restic 0.19.1`, `rclone v1.76.0`). Both archives are owned
  0/0, with 755 on dirs and scripts and 644 on the desktop files. `ventoy.json`
  names the 13.7.0 ISO.
- Failures stop it, as they should:
  - An edited restic SHA256SUMS gave "signature not good … no stick was
    touched".
  - An edited download gave "checksum mismatch", and the file was deleted.
- Tests: 108 passed. New ones in `tests/test_recovery.py`:
  - the list against the doc and the apps;
  - no bash 4 features;
  - `fill-vault.sh` against a stand-in keepassxc-cli: values never in its
    output or arguments, and only what changed is rewritten;
  - `--check` catches a changed file and notes extras.
- shellcheck is clean; CI now shellchecks `recovery/` too.

**Not checked:** a real stick, macOS (`diskutil`, `plutil`, bash 3.2; building
bash 3.2 here wasn't allowed), the real `keepassxc-cli`, and a boot of the new
build. All are in the Backlog.

**Undo:** revert the commit. Nothing outside the repo changed. The old kit is
still in `deprecated/`.

**Next:** the owner's part of phase 5, then flask the same day. In code, W4
(voice) is next.

## 2026-11-18 — W2: the backup repository moves to cellar (code)

**What.** The owner said "next" after W1; W2 was the next item in
[the plan](docs/migration-plan.md). The restic repository now lives on cellar,
in an SFTP-only account, and nothing in the backup code wakes or names
roastery any more. Nothing ran on a node.

**Decisions** (Claude's, open to change):

- **One account for every node, cellar included.** cellar backs itself up over
  SFTP to its own address, like the others. So every file in the repository
  belongs to the account, and any node can read the index another wrote. If the
  hub wrote by path as root instead, its files would be root's and unreadable to
  the rest. Only `drive-sync.sh` reads the folder by path (as root, read-only),
  which was the plan's "let the hub read its own repository by path".
- **Where:** chroot `BACKUP_REPO_ROOT=/srv/backup` (new in `stacks/fleet.env`),
  the repository at `/srv/backup/restic`, seen by the nodes as `/restic`, so
  `BACKUP_REPOSITORY` didn't change. `/srv` must be on cellar's NVMe.
- **One keys file.** `restic/dump-store.keys` became `restic/backup.keys`.
  `repo-setup.sh` and `dump-store-setup.sh` both read it, and cellar's own key
  goes in without a line. Each key is pinned to its node's address (`from=`).
- **rclone stays as restic's SFTP transport.** It was there for Windows; Linux
  wouldn't need it, but it's the path the tests and the old fleet exercised.
  Its built-in remote was renamed `pbroastery` → `pbrepo`.
- **Drive authorization** now runs `rclone authorize` on americano, not roastery.
- **Account name:** `restic` at first, against the cat-breed rule; the owner
  chose `burmilla` the same day.

**Changed:** `stacks/_lib/restic-env.sh` (no wake-on-LAN; `parse_repo`,
`reach_repo`, `repo_local_path`), `stacks/_lib/backup.sh` (`keys` prints one
line for `backup.keys`; `install` also removes a leftover
`purrbrews-wake-roastery` unit), every script in `stacks/backup/restic`, the new
`repo-setup.sh` (with `--check`, which changes nothing), its README, the
systemd unit comments, `stacks/README.md`, `docs/operations.md`,
`docs/migration-plan.md`, and a stale line in `tailscale/README.md`.

**Two existing bugs fixed on the way**, both in files W2 had to change:
`dump-store-setup.sh` looked for nodes in `stacks/<node>` (gone since the
restructure), so it would have refused every line. And its `sshd -T | grep -q`
check warned falsely: with `pipefail`, grep quitting early SIGPIPEs sshd.

**Evidence:**

- Tests: 96 passed as root (the root-only drive-sync and nightly ones
  included); 100 passed as an unprivileged user (the eight that refuse root);
  shellcheck clean. New tests check: the repository is on the hub; nothing live
  wakes roastery; `repo_local_path`; `repo-setup.sh --check` pins each key to its
  address; and it refuses bad lines.
- In the sandbox, against a real OpenSSH server (2026-11-18): `repo-setup.sh`
  made the account and the chroot and reloaded sshd. `restic-init.sh` created the
  repository through the account. A backup and `snapshots` worked. All 14 files
  in the repository were owned by `restic`. A shell command was refused ("This
  service allows sftp connections only"). `sftp` saw only `/restic`, and
  `cd /etc` failed. The same key from another address got "Permission denied".
  `drive-sync.sh` copied the folder by path, and the copy opened with restic.
- Re-run as `burmilla` after the rename (2026-11-18, fresh account): setup,
  init, a backup and `snapshots` worked, with no file in the repository owned by
  anyone else. The rename turned up a fault, now fixed: the account's home had
  been a fixed `/var/lib/purrbrews-repo`, so a renamed account would get a home
  owned by the old one, and sshd ignores keys there. It is `/var/lib/<account>`
  now.

**Not done:** nothing on cellar. Phase 5 is still the owner's: the account,
`restic-init.sh`, each node's keys and `enable`, the restore test.

**Undo:** revert the commit. Nothing outside the repo changed.

**Next:** W3, the recovery kit, or phase 1's owner checks; the plan's order
is the owner's to choose.

## 2026-11-18 — W1: the bootstrap payload; Pi-hole's fleet list fixed

**What.** The owner asked to start the payload. `payload/` is what
purrbrews-bootstrap runs after its own steps to make a machine a node
(`payload/README.md`). `purrbrews-node.sh`, the entry script, does these
steps, each safe to run again:

1. `packages`: installs NetworkManager.
2. `repo`: clones the repo as the ops user; a re-run only fetches.
3. `node`: checks the node exists in `nodes/`.
4. `folders`: makes `/srv/data`, `/srv/media` and `/etc/purrbrews`, and writes `/opt/purrbrews/.env`.
5. `hosts`: lists the other nodes in `/etc/hosts`.
6. `timers`: installs the daily fetch, which never moves the checkout.
7. `network`: last, sets the static address and fixed MAC, detached, with a rollback.

Built from the old `init/`. Node addresses, gateway, LAN and timezone are
read from `stacks/fleet.env` in the new checkout: one source. Root runs only
the payload's own verified files, never files from the checkout, which the
ops user can write to.

**Found on the way.** `stacks/_lib/refresh-dns.sh` still called
`init/purrbrews-mac.sh`, which moved to `deprecated/` on 2026-11-16, so
rendering Pi-hole's records on sieve and mochaPot would have failed. The
tests stub that call, so they didn't catch it. It now reads
`scripts/fleet-macs.sh`, which shares the payload's fleet list
(`payload/lib/fleet.sh`). A test now fails if live code calls the archive.

**Evidence.**
- **MACs unchanged:** `bash scripts/fleet-macs.sh` gives each node the MAC
  the old fleet had (sieve `02:33:68:72:0b:17`, as in `deprecated/README.md`).
- **Tests:** `tests/test_payload.py` (new) runs the `repo`, `node`,
  `folders` and `hosts` steps twice as root against a throwaway checkout and
  an unprivileged ops user. It also checks the MACs, overrides and broken
  lists, the Pi-hole records, and that network is the last step and asks first.
- **Full suite:** passes as root (90+9 run, 8 skipped) and as a normal user.
  shellcheck is clean, and CI now also lints `payload/` and `scripts/`.

**Not done.** The `packages`, `timers` and `network` steps haven't run on a
machine. The payload isn't served from americano yet. Tailscale is still phase 10.

**How to undo.** Revert this entry's commit. Nodes made with it keep their
`.env`, timer and network profile; `nmcli connection delete purrbrews-<iface>`
undoes the address.

**Next step.** The owner serves the payload from americano; then one fresh
machine through the one-liner, twice (phase 1), before sieve.

## 2026-11-18 — Disks re-planned: the ThinkCentres don't boot from M.2 SATA

**What.** The owner reported that the ThinkCentres don't boot from the 128 GB
M.2 SATA drives, so those two are the x360s' boot drives, and that the x360
board (grinder) has a 2.5" SATA bay as a second drive slot. The disks were
re-planned around that (`docs/hardware.md`):

| Node | Was (2026-11-16) | Now |
|---|---|---|
| sieve | 128 GB M.2 SATA | 256 GB SATA SSD (2.5" bay) |
| percolator | 256 GB SATA SSD (OS) + 1 TB NVMe | 1 TB NVMe (OS and data) |
| cellar | 1 TB NVMe | unchanged |
| mochaPot | 128 GB M.2 SATA | unchanged |
| grinder | 512 GB NVMe | unchanged (owner) |

The second 128 GB M.2 SATA drive is the spare, which matters because
mochaPot's SanDisk has a history of command timeouts. grinder's 2.5" bay
stays free.

**Why.** Claude first proposed the 512 GB NVMe for sieve and the 256 GB SSD
in grinder's bay. The owner kept the 512 GB on grinder and put sieve on the
256 GB SSD (2026-11-18 00:48 IST). The old HDDs stay the offline backup copies.

**Changed.** `docs/hardware.md`, and the disk comments in the
`local.env.example` files: percolator now has one disk, and sieve's is the
SATA SSD.

**How to undo.** Revert this entry's commit.

**Next step.** The remaining machine checks (including that a ThinkCentre
boots from a 2.5" SATA SSD); then W1, the bootstrap payload.

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
- **Apps with a newer major were held to their current one** in this first
  pass: n8n on 2.x and OpenCloud on 7.x. Both were then moved on the owner's
  request; see the n8n and OpenCloud paragraph below.
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

**n8n and OpenCloud, and the release notes** (owner, 2026-11-17 21:44:
"update opencloud and n8n as well … read the latest release notes … list any
new functional features"). The notes between each old and new pin were read
from GitHub releases and upstream upgrade docs. The results are in
`docs/image-updates-2026-11.md`. Three corrections and one change came out of it:

- **n8n is 2.48.4, not 2.49.0.** The first pass took the newest tag, and n8n's
  2.49.0 and all of 3.x are betas (pre-releases on GitHub). 2.48.4 is the
  newest stable release. 3.x waits for its stable release.
- **OpenCloud is 9.1.1, not 9.2.0.** 9.2.0 is the rolling channel, which
  upstream says is not for production. 9.1.x is the production line on the
  same image.
- **`THUMBNAILS_TRANSFER_TOKEN` removed** from OpenCloud's compose file and
  secrets: from 9.x OpenCloud ignores it.
- **Every other image was checked against its project's latest stable
  release:** all match. Radicale's image (3.9.1.1) trails upstream's 3.9.2,
  which isn't packaged yet. Meilisearch stays on v1.55.0 for Karakeep.

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
