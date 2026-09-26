# PurrBrews Runbook

Dated design decisions for this repo, newest first. Each entry records *why*, so
changes can be made later without re-deriving the reasoning.

## Backlog / open items

- [ ] Confirm Secret scanning + Push protection are enabled on the public GitHub repo (repo itself already created, pushed, `origin` set)
- [ ] Workstation: DHCP reservation, `bootstrap/data/` (settings + `authorized_keys`), `docker compose up -d --build`, firewall rule for 8443
- [ ] First real node through `bootstrap.sh`, at the console (the network step has not yet run on real hardware)
- [x] Add stacks node by node, each with its own `stacks/<node>/README.md` — sieve, percolator, cellar, mochaPot and grinder are all in
- [x] Pi-hole static leases from `purrbrews-mac.sh`: automated by `stacks/sieve/setup-secrets.sh` (2026-09-15)
- [ ] sieve: Cloudflare DNS token, tunnel + `ntfy.${DOMAIN}` route, healthchecks.io check, then the bring-up in `stacks/sieve/README.md`
- [ ] sieve: prove both alert paths with a deliberate break (stop NetAlertX → ntfy; stop ntfy → ntfy.sh)
- [ ] sieve: router DNS → 192.168.0.10, then hand DHCP to Pi-hole (router DHCP left configured but off)
- [x] percolator: Authelia's 9091 published (UFW: `FORWARD_AUTH_CLIENTS`), session domain `${DOMAIN}`, admin-only rules for `pihole`, `gatus`, `netalertx`, `traefik-sieve` — done in percolator's stack (2026-09-16)
- [ ] percolator: Cloudflare token, then the bring-up in `stacks/percolator/README.md`; `sudo ./firewall.sh`
- [ ] First ForwardAuth round trip from sieve's Traefik to Authelia on real hardware (sandbox-tested with real Authelia 2026-09-16)
- [x] cellar's, mochaPot's and grinder's stacks added, each with its own Traefik (2026-09-16)
- [x] Register cellar, mochaPot and grinder with percolator: `FORWARD_AUTH_CLIENTS` and `admin_hosts` extended, cellar's Traefik built for real (2026-09-16, full fleet repass)
- [x] Migrate Komodo Periphery + Scrutiny collector fleet-wide (sieve, percolator, mochaPot, grinder, roastery) — built from cellar's own service blocks, since `stacks/_templates/komodo-periphery/` never actually landed in the repo (2026-09-16)
- [x] `firewall.sh` for cellar, mochaPot and grinder — none had one before; every published port on them was reachable from the whole LAN with no `ufw route allow` gate (Docker's iptables DNAT bypasses plain `ufw`) (2026-09-16, full fleet repass)
- [ ] Confirm Komodo Periphery's cross-host auth (pinning Core's public key alone) on a real bring-up — only reasoned about and sandbox-built, not tested cross-host; may need its own passkey/API key from Core's UI
- [ ] Confirm the new per-node disk-device vars (`SIEVE_DISK_DEVICE`, `PERCOLATOR_DISK_DEVICE_NVME`/`_SATA`, `MOCHAPOT_DISK_DEVICE`, `GRINDER_DISK_DEVICE`) against real hardware (`lsblk -d -o NAME,TYPE,SIZE,MODEL`)
- [ ] Build `stacks/cellar/smb/` — README/generate-secrets.sh/local.env.example already describe it, but the directory doesn't exist; needs a real decision on shares/permissions, not a guess (found 2026-09-16, full fleet repass)
- [ ] Wire cellar's restic sources to percolator's, sieve's and mochaPot's actual dumps and data — all three now exist in this repo
- [ ] Enable cellar's roastery mirror and Google Drive sync (both scaffolded, neither turned on)
- [ ] roastery: `immich-machine-learning` at Immich's version, Windows Firewall 3003 scoped to percolator
- [ ] Postgres dump job for percolator's databases (Nextcloud, Immich, Paperless)
- [ ] Remaining node: roastery itself joining the fleet; then archive purrBrews-infra
- [ ] Gatus: enable each node's ping as it is provisioned; add app checks as stacks land
- [ ] Optional: paste `purrbrews-mac.sh list --format pihole` into Pi-hole's static DHCP list

### Second brain ([design plan](docs/second-brain/design-plan.md), 2026-09-26)

- [ ] Phase 0: answer open questions Q1 (partner), Q2 (phones), Q3 (away-from-home sync) and record them here
- [ ] Phase 1: `stacks/grinder/syncthing/` (hub, admin-only GUI at `syncthing-grinder.${DOMAIN}`, `firewall.sh` 22000/21027 LAN-only, Authelia `admin_hosts` entry)
- [ ] Phase 1: `stacks/cellar/syncthing/` (receive-only replica, staggered versioning 30 days, GUI on loopback)
- [ ] Phase 1: Obsidian + Syncthing(-Fork) on phone and roastery; global discovery/relays off everywhere
- [ ] Phase 1: vault skeleton + templates in `docs/second-brain/vault-skeleton/`; capture shortcuts on phone and desktop
- [ ] Phase 1 acceptance: every P1 check in the plan, including the 10-of-14-days usage gate
- [ ] Phase 2: restic source `/srv/sync` on cellar; 7 nightly snapshots; one-note restore diff is identical
- [ ] Phase 2: `household` vault on the partner's devices (only if Q1 says yes); `jc` confirmed absent there
- [ ] Phase 3: choose embedding model (Q4) before the first index
- [ ] Phase 3: `stacks/grinder/brain/` (read-only vault mount, `brain` schema, no published port) + Open WebUI tool + Gatus check; every P3 check incl. the isolation test
- [ ] Phase 4: resolve Q6 (grinder → roastery Ollama machine-to-machine auth), then WoL helper + n8n digest/archive/conflict/resurface workflows; every P4 check
- [ ] Pin Open WebUI (`:main`) and Karakeep (`:release`) image tags when grinder is next touched

---

## 2026-09-26 — Second brain: design plan

Full plan: [`docs/second-brain/design-plan.md`](docs/second-brain/design-plan.md).
Nothing is built; this entry records the decisions the build will follow. Items are
in the backlog above.

**Decided (proposed, pending the Phase 0 answers):**

- **Obsidian on a plain-Markdown vault, synced by Syncthing.**
  - The canonical data is text files, readable by any editor, trivially indexed and
    trivially backed up. No new database and no database dump job, which matters while
    the Postgres dump job is still open.
  - Rejected for now: SiYuan and Trilium (own formats, weak offline phone capture) and
    Nextcloud sync (not a real two-way folder sync on Android; it would put notes on
    the household-critical node).
  - Obsidian LiveSync (CouchDB) is the fallback if Syncthing-Fork on Android
    disappoints, or if an iPhone is involved.
  - Memos is deferred: a second place to check is the friction this is meant to remove.
- **grinder is the Syncthing hub and runs the index; cellar keeps a receive-only,
  versioned replica.**
  - grinder was already the second-brain node (`postgres-vector`, `embedding-worker`,
    n8n, Open WebUI, Karakeep).
  - It is "cheap to shed", so it is never the only copy: every device and cellar hold
    full replicas.
  - cellar's replica makes the restic source a local path. Syncthing's versioning
    there is the quick undo; restic is the backup.
- **Karakeep, Paperless and Immich keep links, documents and screenshots.** Notes link
  to them; they are never copied in. Tasks go to Vikunja.
- **Separate vaults (`jc`, `household`, optional `partner`), not folders in one
  vault.** Syncthing shares whole folders per device, so privacy is enforced by which
  devices hold the data at all. The partner's private vault never reaches grinder
  unless she opts in.
- **One new custom service, `brain`, on grinder:**
  - it watches the vaults through a read-only mount, chunks by heading, embeds via
    `embedding-worker`, and stores in `postgres-vector` schema `brain`;
  - it serves `/search` on `grinder_net` only, with no published port;
  - it filters by vault in SQL, per Open WebUI user;
  - the index is derived data and is not backed up.
- **Retrieval always on (CPU); synthesis only when roastery wakes.** Search-only
  answers with links still work when roastery is asleep.
- **Automation writes only into `_ai/` and never edits a human's note.**
  - The inbox auto-archives after 30 days: moved and logged, never deleted.
  - `ai: false` / `_noai/` exclude a note from indexing entirely.
- **LAN-only sync.**
  - Global discovery, relays and NAT traversal are off, and devices are added by hand.
  - 22000/21027 are firewalled to the LAN.
  - The Syncthing GUI is admin-only behind Authelia and has no backdoor port, since it
    can add devices.
- **Rollout is gated on evidence, not enthusiasm.**
  - Phase 3 (AI) needs Phase 1's usage gate (inbox notes on 10 of 14 days) *and*
    Phase 2's restore test.
  - Phase 4 (synthesis) needs a machine-to-machine path to roastery's Ollama that keeps
    Authelia in front. None exists today (`stacks/roastery/traefik/README.md`).

**Found while planning (not fixed here):**

- Open WebUI uses `:main` and Karakeep uses `:release`, against the pinned-images
  principle.
- Karakeep's `NEXTAUTH_URL` is the direct-port URL, while its route is
  `karakeep.${DOMAIN}`. Check that mobile share-sheet sign-in works through the
  hostname.
- Enabling trusted-header SSO on Open WebUI while its 8081 backdoor is published would
  let any LAN client forge the identity header. Don't combine the two.

**Open questions:** Q1–Q11 in the plan's §14. Q1–Q3 block Phase 1; Q4 blocks Phase 3;
Q6 blocks Phase 4.

## 2026-09-16 — percolator joins the fleet: Authelia on 9091, Homepage

percolator was built as if it were the only Traefik, while sieve was built for a
Traefik on every node (entry below). As merged, sieve's admin UIs would have failed
closed. Decided: keep a Traefik per node and publish Authelia for them.

**Authelia's port 9091 is published, but only to Traefik nodes.**

- `FORWARD_AUTH_CLIENTS` in percolator's `.env.local` (default `192.168.0.10`) lists
  the nodes whose Traefik calls ForwardAuth. `firewall.sh` adds one `ufw route allow`
  per IP and rejects anything that isn't a plain address.
- Never opened to the LAN: the port is plain HTTP and also serves the login portal.
  People sign in at `https://authelia.${DOMAIN}` only.
- percolator's own Traefik keeps calling `authelia:9091` by container name.
- The session cookie is for `${DOMAIN}`, so one sign-in covers every node.

**Admin-only hosts are one list in Authelia's config**, `traefik`, `traefik-sieve`,
`pihole`, `netalertx`, `gatus`, with an `allow admins` rule and a `deny` rule for the
same list (a YAML anchor, so the two can't drift). A new node adds its admin hosts there.

**Homepage** (`homepage.${DOMAIN}`, v2.3.0) was on percolator's app list but hadn't
been built.

- Behind ForwardAuth for admins and household.
- No Docker socket and no API widgets, so it holds no credentials.
- Tiles are tracked in `homepage/dashboard/*.yaml`, mounted read-only, and use
  Homepage's own `{{HOMEPAGE_VAR_DOMAIN}}`, so there's nothing to render.

**Pi-hole gets records for percolator's apps.** percolator routes by compose labels,
which sieve's DNS generator didn't read; it now does (see "DNS follows the routes"
below).

**Bugs found by the test:**

- **Household members could open admin pages.** Authelia skips a rule whose subject
  doesn't match and carries on, so a non-admin fell through to the `*.${DOMAIN}`
  household rule. That already applied to percolator's own Traefik dashboard. Fixed
  with the `deny` rule above. Tested before and after.
- **`firewall.sh` exited silently, adding no rules,** when `.env.local` was missing or
  lacked a key: `grep` failing inside `$(…)` under `set -e -o pipefail`. Fixed with
  `|| true`.

**Tested** in a Docker sandbox: real LLDAP and Authelia, percolator's rendered
configs, a sieve-style Traefik on a separate network using sieve's unmodified
`dynamic/sieve.yml`, and ForwardAuth through the published port.

- **Anonymous:** `302` to `https://authelia.${DOMAIN}` for all four of sieve's
  protected hosts.
- **Admin session:** passes to the backend on all four.
- **Household-only session:** `403` on all four and on `traefik.${DOMAIN}`; Homepage
  opens (`200`) with all 14 tiles.
- **Authelia stopped:** sieve answers `500` (fails closed). ntfy needs no auth.
- **Config and scripts:** `authelia validate-config` passes; `docker compose config`
  passes for all 13 apps; `firewall.sh --dry-run` gives the expected rules for zero,
  one and two clients and rejects a CIDR; shellcheck is clean.
- **Homepage:** healthy with read-only config mounts; an unexpected Host header is refused.

**Not tested:** UFW itself on a real node (dry run only), real certificates, and the
Authelia login page in a browser.

## 2026-09-16 — cellar, mochaPot, grinder: three stacks added

Added `stacks/cellar/`, `stacks/mochaPot/` and `stacks/grinder/` — the first
node stacks in this repo, built to `infrastructure.md`'s post-restructure app
placement (§4), not migrated wholesale from the pre-restructure
`purrBrews-infra` build. Each node's own README states this plainly and lists
what changed. Summary here is cross-cutting decisions only.

**cellar** (192.168.0.12) — restic, Samba/NFS, Scrutiny hub, Komodo Core
+ Mongo:

- **restic replaces `backup-mirror/` outright**, not just in name. The
  2026-09-13 fleet audit's Tier 0 #1 found that `backup-mirror/mirror.sh`
  defined `mirror_source()` and never called it — nightly, silently, copying
  zero bytes, the whole time it existed. The new `restic/` scripts are real,
  runnable `restic backup` calls per source (still empty — percolator,
  sieve and mochaPot all exist in this repo now, but the actual dump
  sources aren't wired up yet, tracked in the backlog), not another
  function definition nobody invokes.
- **Scrutiny's hub and Komodo's Core + Mongo both moved here from the
  pre-restructure `silo`**, which no longer exists as a role
  (`infrastructure.md` §1's retirement note). Komodo's OIDC login is
  deliberately left off (`KOMODO_OIDC_ENABLED: "false"`) — percolator's
  Authelia exists in this repo now, but cellar isn't registered with it yet
  (see the backlog); local admin auth only until then.
- **Vaultwarden and Caddy are gone from cellar**, not lost — moved to
  percolator per the new app table. Nothing in this rebuild tries to recreate
  them.
- **NFS stays host-native**, same call the pre-restructure build made
  (containerized NFS servers still aren't recommended) — this time actually
  implemented (`nfs/setup-nfs.sh`), not just documented as a someday step.

**mochaPot** (192.168.0.13) — Home Assistant + PG, Music Assistant, Pi-hole
(secondary, DNS only), kiosk browser:

- **Home Assistant moved here from percolator** — `infrastructure.md` §4:
  "shares a failure domain with neither the app tier nor the network tier,
  the wall dashboard renders locally if percolator is down." No Traefik/
  Authelia in front of it here, unlike its old placement — the alpha-stage
  OIDC component isn't carried over either.
- **The kiosk browser is genuinely new** — cage (Wayland kiosk compositor) +
  Chromium, autologin on a dedicated `kiosk` user, not `barista`. Host-native.
- **Pi-hole here keeps a real web password**, unlike sieve's (which disables
  it in favor of Authelia's ForwardAuth) — mochaPot has no reverse proxy at
  all, so this instance's own login is its only gate.
- Jellyfin/Immich/Vikunja/n8n/FreshRSS/Mealie/Actual Budget/Stirling PDF/
  Roundcube/Traefik, everything else the pre-restructure mochaPot ran, moved
  elsewhere or were cut (`infrastructure.md` §4's "Deliberately not
  running").

**grinder** (192.168.0.14) — n8n, embedding worker, PG + pgvector, Open
WebUI, Karakeep, FitTrackee, Traccar, ESPHome dashboard, Speedtest Tracker:

- **grinder did not exist pre-restructure** — entirely new node, entirely new
  stack directory.
- **`embedding-worker` is custom-built, not a pulled image** — no published
  image exists for this project's specific "small CPU embedding API n8n
  calls" shape, so it's a small FastAPI + sentence-transformers service built
  from a `Dockerfile` in this repo. Registry image monitoring cannot track what
  `pip install` pulled into this local build — flagged
  in the node's own README, not solved here.
- **Every app gets its own dedicated Postgres** where it needs one
  (`postgres-vector` for the embedding pipeline, `postgres-fittrackee` for
  FitTrackee) — same discipline percolator's `homeassistant/docker-compose.yml`
  documents the reasoning for (a real port collision, pre-restructure, from
  sharing one Postgres layer across unrelated apps).
- **Traccar keeps its bundled H2 database**, deliberately not given its own
  Postgres like FitTrackee — high-write low-value telemetry, not judged worth
  the extra backup weight yet.
- **Open WebUI has no automated wake path to roastery's Ollama.** Ollama on
  Windows only answers once someone's logged in and the tray app is running
  (`infrastructure.md` §9) — nothing here sends the WoL packet before a chat
  request; `cellar/restic/mirror-to-roastery.sh`'s WoL-then-wait pattern is
  flagged as the reusable shape for this, not yet adapted.

**Common to all three**: `generate-secrets.sh` now uses `openssl rand -hex`,
not `-base64`, for every new secret (`infrastructure.md` §6 — the RFC 6749
§2.3.1 URL-encoding bug that broke Mealie pre-restructure is a base64-only
failure mode; hex removes the bug class rather than requiring `client_secret_basic`
to be audited per app). Traefik was added to all three the same day (each node's own
README says so under "Traefik and the native-login backdoor"), each
already pointing its `authelia-forwardauth` middleware at
`http://${PERCOLATOR_LAN_IP}:9091/api/authz/forward-auth` — percolator's
real endpoint, which now exists in this repo (see the entry above). What's
still missing is registration on percolator's side: each of these three
IPs in `FORWARD_AUTH_CLIENTS`/`firewall.sh` and in Authelia's admin-host
list, tracked in the backlog below. Until then every `*.${DOMAIN}`
hostname on these nodes 502/504s through Traefik; the direct-port
backdoor each README describes is what actually works today.

## 2026-09-15 — percolator: ingress, identity and daily apps

percolator (`.11`) runs Traefik, CrowdSec, LLDAP, Authelia + Redis, Vaultwarden,
Nextcloud + Postgres + Valkey, Immich + Postgres + Valkey, Paperless-ngx + Postgres +
Valkey, Mealie, Vikunja, Actual Budget and FreshRSS. Everything is in
`stacks/percolator/`; each app has its own README with first-run steps and an
"is it working?" checklist.

**Why these sit together:** ingress and identity on the same host as the apps means
one Docker network and routing and ForwardAuth by container name for percolator's
own apps. Other nodes' Traefik reach Authelia on its published port 9091; see the
2026-09-16 entry, which replaces this entry's original "no published auth port".

### Layout decisions

- **One `proxy` network with a fixed subnet** (`PROXY_SUBNET`, default
  `172.30.0.0/24`). Traefik and each app's web container join it; every app lists
  it as its trusted proxy. Only Traefik publishes ports (80/443). LLDAP's admin port
  is bound to `127.0.0.1` as break-glass.
- **Every database is private to its app.** Each Postgres and Valkey is on its own
  project's network only, with an app-prefixed container name. Nextcloud gets its
  own Valkey for file locking; Paperless needs one as its task broker.
- **`authelia.${DOMAIN}` is a Docker network alias of Traefik.** Apps fetch OIDC
  discovery and exchange tokens through Traefik with a valid certificate, without
  depending on LAN DNS being in place.
- **One wildcard certificate** (`${DOMAIN}` + `*.${DOMAIN}`) via Cloudflare DNS-01:
  fewer ACME orders, no inbound port 80, and app names don't appear individually in
  certificate-transparency logs.
- **Traefik `readTimeout: 0s`.** v3's 60 s default cuts off large uploads.

### Identity

- **Groups:** `purrbrews_admins` (Traefik dashboard, Mealie admin) and
  `purrbrews_household`. Authelia refuses OIDC sign-in to anyone in neither group,
  via a custom `household` authorization policy, before the app sees them.
- **`AUTH_POLICY`** (`one_factor` for now) is one variable used by every rule and
  client, so moving to two-factor is a single edit once everyone has enrolled.
- **All OIDC client secrets are generated on the node.** App plaintext and Authelia's
  PBKDF2 hash are written in the same run of `generate-secrets.sh`, since Authelia
  and all eight apps share the node. No copy step, nothing to drift.
- **Secrets are hex.** base64's `+ / =` break `client_secret_basic` in clients that
  don't URL-encode the secret, even when both sides hold the identical string.
- **Hashes are written single-quoted** so neither bash `source` nor compose's
  env-file parser expands their `$`.
- **The OIDC signing key is generated by the script** and stored as one line with
  literal `\n`, un-escaped by a double-quoted YAML string. envsubst knows nothing
  about YAML indentation, so a multi-line PEM would break the file.
- **Vaultwarden's admin token is an Argon2id hash** produced by the Authelia image;
  the plaintext stays in the secrets file for typing at `/admin`.
- **`lldap-bootstrap.sh`** creates both groups and any user, idempotently, through
  LLDAP's GraphQL API and its bundled `lldap_set_password`.

### CrowdSec: bouncer in Traefik, not the host firewall

Everything reaching percolator's apps comes through Traefik, and tunnel visitors
arrive from sieve's LAN address. A host firewall bouncer sees only that address,
which the default whitelist never bans, so it would enforce nothing. Instead:

- **The Traefik bouncer plugin** blocks by the real client address, taken from
  `X-Forwarded-For` trusted only from `SIEVE_IP`.
- **It is registered with `BOUNCER_KEY_traefik`,** using a key generated on the node;
  no `cscli bouncers add` step.
- **`updateMaxFailure: -1`:** if CrowdSec is down, Traefik keeps serving with the last
  decisions instead of blocking the household.
- **`clientTrustedIPs` = LAN,** so the bouncer never blocks LAN clients.
- **The plugin is a Traefik *local* plugin,** cloned by `traefik/prepare.sh` at a
  pinned tag and verified against its commit SHA. A catalog plugin is downloaded on
  every Traefik start. When that download failed in testing, the `crowdsec@file`
  middleware became invalid, and every route on the entry point went dark with it.

### Tooling

- **`render-configs.sh` refuses a template with an unset or empty variable.** envsubst
  silently substitutes `""` and exits 0.
- **Each template renders in its own subshell,** so one app's secrets never reach
  another's config.
- **Rendered files are 0600** unless the template opts into 0644.
- **Failures are collected and listed at the end,** and the script exits non-zero.
- **`compose.sh` checks before `up`:** it refuses REPLACE_ME placeholders, and rendered
  configs that are missing or older than their template, `.env.local` or the app's
  secrets.
- **It then creates data directories from `<app>/data-dirs`** with the owner the image
  needs, and runs `<app>/prepare.sh`. `--all` brings the node up in dependency
  order, and down in reverse.
- **It uses `sudo docker` itself;** the scripts refuse to run under sudo, so secrets
  files never become root-owned.
- **`setup-secrets.sh` appends keys** added to `local.env.example` after `.env.local`
  was created.
- **`firewall.sh`** holds the node's only UFW additions: `ufw route allow` for 80/443
  from the LAN, since published ports go through ufw-docker's FORWARD rules.

### Tested

Tested in a Docker sandbox with a stand-in `/opt/purrbrews/.env`, as a non-root ops
user with sudo.

- **Scripts:**
  - `setup-secrets.sh` ran end to end; a second run left every secrets file and
    `.env.local` byte-identical.
  - `render-configs.sh` refused a template with an emptied `SIEVE_IP` and rendered
    the rest.
  - `compose.sh` refused a stale render and a failed `prepare.sh`.
  - shellcheck is clean.
- **Compose and config:**
  - `docker compose config` passes for all 12 apps.
  - `authelia validate-config` passes on the rendered configuration.
  - `authelia crypto hash validate` matched a generated client secret to its hash.
- **Identity:**
  - `lldap-bootstrap.sh` ran as a dry run, then created the groups and user, and a
    re-run changed nothing.
  - Authelia first-factor login as the new user worked. The Traefik dashboard
    redirected to Authelia and opened after login.
  - Container DNS resolved `authelia.${DOMAIN}` to Traefik on `proxy`.
- **OIDC:** all 8 clients authenticated at Authelia's token endpoint with their
  generated secret and configured auth method (`invalid_grant` on a dummy code).
  A wrong secret gave `invalid_client`.
- **Traefik and CrowdSec:**
  - The local plugin loaded.
  - With CrowdSec unreachable, Traefik kept serving.
  - The access log was written.
  - The Nextcloud `.well-known/caldav` redirect worked.
- **Apps:**
  - Vaultwarden's `/admin` accepted the password against the Argon2id token and
    rejected a wrong one.
  - Every container started and passed its healthcheck where it has one.
  - Nextcloud installed (34.0.4) with the proxy settings and Redis locking applied.
  - Immich answered `/api/server/ping`.
  - Paperless ran migrations and offered Authelia sign-in.
- **Bugs found and fixed by the test:**
  - `envsubst --variables` needs its input as an argument, so the unset-variable
    guard was silently checking nothing.
  - Postgres 18 couldn't start under a root-owned 0700 parent directory; it is now
    created as 999:999.
  - Paperless's server binds `::` by default and dies on a kernel with IPv6
    disabled; it now binds `0.0.0.0`.
- **Not tested (no real domain or certificate in the sandbox):**
  - ACME issuance.
  - Browser OIDC round-trips for each app.
  - Actual Budget and Vikunja startup against a trusted Authelia certificate. Both
    retried against the sandbox's self-signed certificate, as expected.
  - CrowdSec hub download and a real ban through the tunnel.
  - Nextcloud's `user_oidc` install.

## 2026-09-15 — A Traefik on every node; SSO stays central

Each node runs its own Traefik for its own apps, instead of one Traefik on percolator
fronting the fleet. The goal is blast radius: a bad route, a broken proxy or a dead
node takes down that node's pages only.

**What stays shared: login.**

- Authelia runs once, on percolator. Every node's Traefik uses a ForwardAuth
  middleware against it, so there's still one SSO session across `${DOMAIN}`.
- **Accepted trade-off:** if percolator is down, protected UIs on other nodes fail
  closed (`500`). Anything with its own accounts (ntfy) or no UI (DNS, DHCP, the
  tunnel, alerting) is unaffected.
- On sieve, loopback SSH forwarding opens the UIs without SSO, as break-glass.

**The ForwardAuth hop must be direct:** `http://<percolator>:9091/api/authz/forward-auth`.

- Through percolator's Traefik (`https://auth.${DOMAIN}/…`), the second proxy rewrites
  or drops `X-Forwarded-Method/Host/Uri` and Authelia returns `400`.
- Authelia also refuses targets with an `http` scheme, so every protected router is
  HTTPS with a real certificate.
- Tested on sieve against a stub auth server: unauthenticated requests are redirected
  to login, a valid session passes, and the auth call carries `X-Forwarded-Method`,
  `Proto=https`, `Host` and `Uri`.

**Per node:**

- Certificates by DNS-01. No two nodes request the same set: percolator holds the
  `*.${DOMAIN}` wildcard, other nodes use one certificate per router. Otherwise they
  share Let's Encrypt's five-identical-certificates-a-week limit, and a couple of
  rebuilds exhaust it.
- Routes in file-provider YAML read as Go templates (`{{ env "DOMAIN" }}`), so there's
  no render step. No Docker socket.

**DNS follows the routes, not a wildcard.** sieve's
`setup-secrets.sh` reads every node's router rules and writes
`address=/<name>.${DOMAIN}/<node IP>` for Pi-hole, so a route and its DNS record
can't drift apart. It reads sieve's `traefik/dynamic/*.yml`, percolator's
`traefik/config/*.template` and compose labels. Tested with percolator's stack in
the repo: its 11 names resolve to `.11`, and sieve's 5 to `.10`. The remaining manual step: re-run it on
sieve after adding a route. The first version also matched an example `Host(...)` in
a comment; it now reads only `rule:` lines.

## 2026-09-15 — sieve: the network stack

sieve (.10) runs the six apps that keep the house online and report problems —
Pi-hole (DNS + DHCP), Unbound, cloudflared, ntfy, Gatus and NetAlertX — plus its own
Traefik (entry above). It runs nothing else, so app work never reboots the network.

**DNS: Pi-hole → Unbound, on the same host, with no published resolver port.**

- Unbound sits on its own bridge (`sieve_dns`, fixed `172.31.53.2`). Pi-hole uses host
  networking and reaches it over that bridge, so the resolver is unreachable from the
  LAN by construction. That avoids a firewall rule or a 5335 remap.
- Unbound's access list uses the most-specific match, whatever the order. The image
  already allows `192.168.0.0/16` and `172.16.0.0/12`, so the overrides must be more
  specific: allow the bridge gateway `/32`, refuse the bridge `/28`, refuse the LAN
  `/24`. A `0.0.0.0/0 refuse` would lose to the image's `/16` allow.
  Tested: the host is answered; another container on the bridge gets `REFUSED`.
- Unbound is not `read_only`: it rewrites `root.key` on trust-anchor rollovers.

**Pi-hole is configured entirely by `FTLCONF_*` variables.** Nothing is clicked in the
UI, and a rebuilt container is identical.

- Upstream, DHCP range, 7-day lease and the NTP server (off) are in the compose file.
  Static leases and host names for every node come from `init/purrbrews-mac.sh`,
  generated into `.env.local` by `setup-secrets.sh`.
- App host names come from every node's Traefik routers (entry above).
- `filter-AAAA` stops IPv6-preferring clients using a public AAAA to bypass a local
  record.
- Tested against a fake upstream: a local record answers A, AAAA is filtered, and a
  `server=/name/#` exemption forwards as expected.
- **DHCP starts off** (`PIHOLE_DHCP_ACTIVE=false`) and is handed over deliberately.
  - Two DHCP servers on one LAN is the failure to avoid.
  - `67/udp` must be open from *any*: a client's first request comes from `0.0.0.0`.
  - The 7-day lease gives ~3.5 days of grace; the router's DHCP stays configured but
    off, as break-glass.

**Admin UIs have no login of their own; sieve's Traefik + Authelia is the gate.**

- Pi-hole (8080) and NetAlertX (20211) run on host networking with auth disabled.
  `firewall.sh` opens those ports to `sieve_edge` only (Traefik and Gatus), never the
  LAN. Gatus publishes no port at all.
- NetAlertX has unauthenticated-RCE history, so its API port (20212) gets no rule, and
  none of these UIs may ever be routed through the tunnel.
- NetAlertX settings are forced with `APP_CONF_OVERRIDE` (subnet + interface, password
  off, `BACKEND_API_URL=/server`, so only 20211 needs proxying). Tested: all show as
  overridden by env.
- ntfy is served on the LAN by sieve's Traefik, and outside by the tunnel. Phones at
  home get alerts even with the WAN down.

**Tunnel and notifications.**

- cloudflared is token-based and remotely managed. Routes are in the Cloudflare
  dashboard, recorded in `cloudflared/README.md`, because nothing else captures them.
- Two lessons are written in advance for routes to a node's Traefik:
  - use `https://…:443`, since `http://:80` loops on Traefik's redirect;
  - set the Origin Server Name, or TLS fails on Traefik's default certificate.
- ntfy is public through the tunnel with `deny-all`, no sign-up, and declarative users,
  ACLs and tokens (`NTFY_AUTH_*`, re-applied each start). Passwords are bcrypt-hashed by
  ntfy's own `user hash` via `docker run`. Tested: Gatus's token can publish but not
  read; anonymous access gets 403; an extra read-only user works.

**Alerting in three layers**, since a monitor can't report its own death:

1. Gatus → self-hosted ntfy for routine alerts.
2. Gatus → public ntfy.sh (a random 24-hex topic) when the failure is the delivery
   path itself (ntfy, the tunnel).
3. Gatus pings healthchecks.io every 5 min, and healthchecks.io alerts on silence (sieve,
   Gatus or the WAN dead).

Gatus reads its tracked config and substitutes `${VARS}` itself, so no secret is
rendered to disk. It alerts straight to the ntfy container rather than through
Traefik, and checks the certificate plus the SSO answer on a real `https://` request
resolved through Pi-hole. Tested: failing checks delivered alerts to the ntfy topic. The
ntfy.sh path couldn't be exercised from the sandbox (TLS interception), so the
deliberate-break test is in the backlog.

**Bug found while testing:** a Gatus HTTP check with only `[STATUS] < 400` passed
against a stopped service, because a refused connection reports status 0. Every
HTTP check now also requires `[CONNECTED] == true`, and `stacks/README.md` says so.

**Scripts.**

- `setup-secrets.sh` appends keys that are new in `local.env.example` to an existing
  `.env.local`. Without that, a key added later silently stays unset on nodes that
  already have the file.
- It detects the LAN interface, builds Pi-hole's host lists, creates data directories
  and calls `generate-secrets.sh`.
- Both scripts refuse to run as root (root-owned files break the next run) and use
  sudo only where needed.
- Secrets are hex (`openssl rand -hex`). Values are single-quoted, because bcrypt
  hashes contain `$`.
- `compose.sh` loads `/opt/purrbrews/.env`, `.env.local` and the app's secrets, runs
  Docker via sudo, creates `sieve_edge` with its fixed subnet, and supports `all`.
- `firewall.sh` holds every rule (`ufw allow` for host-network apps, `ufw route allow`
  for published ports) and supports `--dry-run`.

**Tested** in a Debian container with Docker, as a non-root ops user:

- `setup-secrets.sh` from nothing, then re-run: byte-identical files;
- `docker compose config` for all six apps;
- all seven containers up (Pi-hole, NetAlertX, ntfy and Traefik healthy);
- Traefik routing and ForwardAuth against a stub auth server;
- every `firewall.sh` rule accepted by `ufw --dry-run`;
- shellcheck clean.

**Not tested:**

- real recursion to the root servers (the sandbox has no outbound DNS);
- a real tunnel;
- Let's Encrypt issuance (the sandbox intercepts TLS);
- real Authelia;
- ntfy.sh delivery;
- ICMP checks;
- DHCP on a real LAN;
- NetAlertX scan results.

The bring-up table in `stacks/sieve/README.md` has a check for each.

## 2026-09-15 — Public repository, zero secrets in transit

The GitHub repository is **public**. Nodes clone and pull it anonymously over https, so
there are no tokens, deploy keys or credential helpers anywhere.

- **Secrets are generated on each node** by `generate-secrets.sh` into gitignored
  `secrets.env.local` files. They are never committed, not even encrypted.
- **The bootstrap container serves only public material:** scripts, public SSH keys and
  fleet settings. It needs no password.
- **The ops user's sudo password** is typed at each node's console, or generated with
  `--yes`. A password hash is accepted only from a local root-only settings file, never
  from the bootstrap server.
- **Guards:**
  - `purrbrews-init.sh` rejects a `GITHUB_TOKEN`, a non-https `REPO_URL` and credentials
    embedded in the URL.
  - The bootstrap container refuses to start, and `bootstrap.sh` refuses to continue, if
    the served settings contain `OPS_PASSWORD_HASH` or `GITHUB_TOKEN`.

## 2026-09-15 — Fleet naming, static addressing, cloned MACs

**Nodes:** sieve .10, percolator .11, cellar .12, mochaPot .13, grinder .14 on
192.168.0.0/24. `.1`–`.5` are reserved for routers and switches.

**Every node carries a cloned MAC** in the same NetworkManager profile as its static IP,
so both change together in one link change.

- **Derivation:** the MAC is derived from the node name as `02:` + the first 5 bytes of
  sha256("purrbrews:<lower-case name>").
  - It is locally administered, so it can't collide with a vendor MAC.
  - It is stable across reinstalls and NIC swaps, and needs no record kept.
  - `NODE_MACS` overrides it per node.
- **Rejected before anything changes:** duplicate names, IPs and MACs; multicast MACs;
  unknown node names; Wi-Fi interfaces.
- **Wake-on-LAN** still uses the burned-in MAC.
- **Tooling:** `init/purrbrews-mac.sh` lists the MACs (table, Pi-hole, dnsmasq, CSV),
  compares expected, current and burned-in MACs on a node, and re-applies them.

**How the network switch runs:**

- It runs detached (`systemd-run`), so a dropped SSH session can't interrupt it.
- **Success** requires all of these:
  - the new address and MAC are on the link;
  - the default route goes via `GATEWAY`;
  - the gateway answers.
- **Otherwise** the old profile and MAC are restored within 60 s.
- **Re-runs** build `purrbrews-<iface>-next` and swap it in only after it has proven
  itself.
- A second run while a switch is in progress is refused.

## 2026-09-15 — Bootstrap served from the workstation

`bootstrap/` builds `purrbrews-bootstrap`, an nginx 1.29.8-alpine container for Docker
Desktop. It serves:

| Path | Content |
|---|---|
| `/bootstrap.sh` | the node one-liner; base URL injected per request |
| `/files/*` + `SHA256SUMS` | `init/`, baked in at build |
| `/keys/authorized_keys` | live from `bootstrap/data/` |
| `/config/purrbrews-init.env` | live fleet settings, no secrets |

**TLS pinning:**

- A self-signed key lives in a named volume, so it survives rebuilds.
- Nodes pin it on first contact: strictly with `PB_PIN`, or trust-on-first-use with a
  confirmation prompt.
- The pin is stored on the node, so the hourly key sync is pinned too.

**Container hardening:** read-only root filesystem, all capabilities dropped except
those nginx needs, `no-new-privileges`.

**Key sync exit codes:**

| Code | Meaning | Unit result |
|---|---|---|
| 0 | ok | success |
| 75 | source unreachable (workstation asleep); nothing changed | success |
| 1 | TLS pin mismatch or any other error | failed |

Accepted trade-off: revoking a key takes effect once the workstation is awake.

## 2026-09-15 — `init/`: one-command node provisioning

`init/purrbrews-init.sh` takes a fresh Debian 13 install to "only the stacks are left".
It runs as named, individually re-runnable steps.

**Security model:**

- SSH is key-only, with no root login, via a validated `sshd_config.d` drop-in.
- The drop-in refuses to apply until a key is installed.
- `barista` reaches root only through a password-gated `sudo`, and is never in the
  `docker` group.

**Settings:** one KEY=value file, parsed and never sourced. It tolerates CRLF line
endings and a UTF-8 BOM.

**Timers:** systemd timers with `Persistent=true`, so a missed daily pull runs at boot.
Pulls are fast-forward only, refuse a dirty tree, never restart containers, and can ping
healthchecks.io.

**Firewall:** UFW rules are additive, so re-runs never wipe per-app rules. SSH is allowed
from the LAN only. ufw-docker is pinned to a release tag and verified by SHA-256.

**Also:** Docker log rotation (10 MB × 3), a journal size cap, masked suspend targets,
and a generated `/opt/purrbrews/.env` (NODE, NODE_IP, TZ, PUID/PGID, paths).

**Tested** in systemd Debian 13 containers, end to end through the bootstrap container:

- **Idempotency:** a full run, then a re-run, left config files and firewall rules
  byte-identical.
- **SSH:** key login works; password and root logins are refused; a key revoked at the
  source is locked out after one sync.
- **Key sync edge cases:** an unreachable source leaves keys unchanged; a pin mismatch is
  a hard failure.
- **Pull timer** fast-forwards, and refuses on a dirty tree.
- **Network switch on a NetworkManager-managed link behind a simulated gateway:**
  - DHCP → static + cloned MAC works; re-runs are no-ops.
  - A MAC change swaps in cleanly.
  - A wrong gateway rolls back in about 65 s.
- **Bugs found and fixed while testing:**
  - Re-runs deleted the live network profile before building the new one.
  - Overlapping runs could apply a wrong gateway.
  - After a rollback, the old MAC was not restored.
  - Terminal detection accepted a tty that couldn't be opened.
  - A leaked `umask 077` made later config files root-only.
- **Not yet tested:** real hardware (including the ifupdown → NetworkManager path on a
  netinst install) and Docker Desktop on Windows.

## 2026-09-15 — Repository conventions

- **Line endings:** `* text=auto eol=lf`, since the repo is authored on Windows and
  deployed to Linux.
- **`.gitignore`:** names specific sensitive files rather than using blanket patterns
  that could hide legitimate files.
- **No placeholder folders:** node and app directories appear with their first real file.
- **Default branch:** `main`.
