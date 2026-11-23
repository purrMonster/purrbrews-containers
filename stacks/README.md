# stacks

One folder per app, grouped by what the app is for; one small folder per machine
under [`../nodes/`](../nodes/). Every node works the same way: the scripts are
identical three-line wrappers around [`_lib`](_lib/), and everything that differs
between nodes or apps is a small config file, not code.

Until the 2026-11 rebuild this tree was organised by node (`stacks/<node>/<app>`),
which meant five copies of Traefik and of each node agent. Now an app has one home
whichever machine runs it, and a node is just the list of apps it runs
([`../docs/carry-over-map.md`](../docs/carry-over-map.md) says where everything went).

```
stacks/
├── fleet.env                  LAN facts every node shares (IPs, gateway, TZ, backups). Committed, not secret
├── _lib/                      the actual scripts (see below)
└── <group>/<app>/             network, identity, mail, apps, home, automation, ai,
    │                          monitoring, fleet-management, backup
    ├── docker-compose.yml
    ├── README.md              first run, "is it working?" (for apps that need one)
    ├── secrets.conf           what setup generates or asks for      (optional)
    ├── firewall               this app's UFW rules                  (optional)
    ├── data-dirs              directories created before `up`       (optional)
    ├── backup                 what gets dumped and backed up         (optional)
    ├── prepare.sh             run before `up`                       (optional)
    └── config/*.template      rendered next to themselves           (optional)

nodes/<node>/
├── README.md                  role, apps, bring-up order, gotchas
├── node.conf                  APPS in bring-up order, TOOLS, NETWORK, RESOLVER, BACKUP_HUB
├── local.env.example          node settings template → .env.local (gitignored)
├── setup-secrets.sh           ┐
├── render-configs.sh          │ the same wrapper on every node:
├── compose.sh                 │ exec ../../stacks/_lib/<script> <this dir> "$@"
├── firewall.sh                │
└── backup.sh                  ┘
```

App names are unique across the groups, so a node's `APPS=(…)` lists bare names and
`_lib` finds each folder. `TOOLS=(…)` lists host-side folders that aren't containers
but have settings or templates (`restic` on every node, `kiosk` on mochaPot).

| Group | Apps |
|---|---|
| `network` | unbound, pihole, pihole-secondary, cloudflared, netalertx, crowdsec, and the three Traefiks: `traefik-edge` (sieve), `traefik-ingress` (percolator), `traefik` (every other node) |
| `identity` | lldap, authelia |
| `mail` | mail-relay |
| `apps` | vaultwarden, opencloud, radicale, immich, paperless, mealie, vikunja, meowgram, actualbudget, freshrss, homepage, purrcafe, karakeep, fittrackee, traccar |
| `home` | homeassistant, musicassistant, esphome, kiosk |
| `automation` | n8n, postgres-vector, embedding-worker, pourover |
| `ai` | litellm (the door to a cloud model), openwebui, immich-ml |
| `monitoring` | gatus, ntfy, speedtest-tracker |
| `fleet-management` | komodo, komodo-periphery, scrutiny, scrutiny-collector, persian-perch |
| `backup` | restic, smb, nfs |

| Node | Role | |
|---|---|---|
| `sieve` | Network: DNS, DHCP, tunnel, alerting | [nodes/sieve](../nodes/sieve/README.md) |
| `percolator` | Ingress, identity (SSO) and the daily apps | [nodes/percolator](../nodes/percolator/README.md) |
| `cellar` | Backups (the repository too, since the rebuild), file shares, Komodo, the Scrutiny hub, Home Assistant | [nodes/cellar](../nodes/cellar/README.md) |
| `mochaPot` | Music, the wall screen, secondary DNS | [nodes/mochaPot](../nodes/mochaPot/README.md) |
| `grinder` | Automation, AI (LiteLLM, Immich ML), self-tracking | [nodes/grinder](../nodes/grinder/README.md) |

roastery, the Windows workstation, is out of the fleet; its stacks and PowerShell
twins are under [`../deprecated/`](../deprecated/ABOUT.md).

### Adding an app, or moving one

A new app is a folder under the group it belongs to and one word in a node's
`APPS`. Moving an app to another node is deleting the word from one `node.conf` and
adding it to another (plus its settings in that node's `local.env.example`): the
network is called `proxy` on every node, so the compose file doesn't change.

## The shared scripts

Run them from the node's folder, as the ops user, never with sudo (they sudo the
few commands that need it; root-owned secrets files break the next run).

| Script | Does |
|---|---|
| `./setup-secrets.sh` | First-time setup, and the thing to re-run after a pull. `.env.local` from `local.env.example` (new keys appended, [renamed keys](_lib/renamed-keys) copied across), a prompt for every `REPLACE_ME`, every app's `secrets.conf`, then render. Never changes a value that's already set |
| `./render-configs.sh` | Every `*.template` → the file beside it. A template with an unset or `REPLACE_ME` variable fails and its last good render stays. On a node with `RESOLVER` set, regenerates the Pi-hole records first |
| `./compose.sh <app> …` | `docker compose` with the env files. Before `up` it checks renders are current, creates `data-dirs`, runs `prepare.sh`, and refuses a resolved config with a `REPLACE_ME` left in it. `--all` goes in `node.conf` order (backwards for `down`); `--list` prints that order. An app this node's `node.conf` doesn't list is refused |
| `sudo ./firewall.sh` | UFW rules from every app's `firewall` file; `--dry-run` prints them |
| `sudo ./backup.sh <cmd>` | The node's backups from every app's `backup` file: `plan` (no sudo), `doctor`, `keys`, `nightly`, `restic …`. See [Backups](#backups) |

**Env files, later ones win:** `stacks/fleet.env` → `/opt/purrbrews/.env` (written when
the node is set up: `NODE`, `NODE_IP`, `PUID`/`PGID`, `DATA_DIR`, `MEDIA_DIR`) → the node's
`.env.local` → the app's `secrets.env.local`. The renderer and compose see exactly
the same values.

### secrets.conf

One line per key; `_lib/secrets.sh` has the details.

```
LLDAP_JWT_SECRET                  hex 64                  # random hex, 64 chars
HA_DB_USERNAME                    value homeassistant     # a fixed default
CF_DNS_API_TOKEN                  prompt Cloudflare API token (…)
PERIPHERY_ONBOARDING_KEY          prompt optional …       # blank is a valid answer
AUTHELIA_LDAP_PASSWORD            copy lldap LLDAP_ADMIN_PASSWORD
GATUS_NTFY_TOKEN                  mirror ntfy GATUS_NTFY_TOKEN   # re-copied every run
VAULTWARDEN_ADMIN_TOKEN           hash argon2 VAULTWARDEN_ADMIN_PASSWORD
IMMICH_OIDC_CLIENT_SECRET_HASH    hash pbkdf2 immich:IMMICH_OIDC_CLIENT_SECRET
AUTHELIA_OIDC_JWK_PRIVATE_KEY     rsa 2048
NOTE copy RESTIC_PASSWORD to flask if you haven't yet
```

Hashes are made with the app's own image (the tag is read from the node's compose
files). Anything odder goes in `<app>/secrets.hook`, sourced afterwards (sieve's ntfy
builds its user lists that way). To rotate a value, delete its line from
`secrets.env.local` and run setup again.

### firewall

```
allow tcp 8123 LAN       # homeassistant ui from LAN
allow tcp 8123 NETWORK   # homeassistant from proxy
route tcp 9091 $FORWARD_AUTH_CLIENTS  # authelia forward-auth
```

`allow` for host-networked apps (INPUT); `route` for published container ports, which
Docker DNATs through FORWARD. A `route` rule matches the **container** port, not the
published one. `LAN` is `LAN_CIDR`, `NETWORK` is the subnet of the node's `NETWORK`,
`$KEY` is any setting (a list gives one rule each). An optional fifth field is the
destination (sieve uses `NETWORK` there). The script only adds rules; remove old ones
with `sudo ufw status numbered` / `sudo ufw delete <n>`.

It also re-applies `ufw-docker install --docker-subnets` first. ufw-docker's plain
install lets any private address (the whole LAN included) past these rules, so for
a long time the `route` rules restricted nothing. With `--docker-subnets` only
Docker's own networks skip them; since that list is taken at run time, run
`sudo ./firewall.sh` again after a new network appears.

### data-dirs

```
paperless/consume PUID:PGID 2775
MEDIA_DIR/household PUID:PGID 755
```

Created before `up` if missing, never touched after. Without it Docker creates a
bind-mount source as `root:root`, and an image that runs as a fixed user crash-loops.

### backup

```
pg      immich  immich-postgres  immich  immich   # pg_dump inside the app's own container
mongo   komodo     komodo-mongo  $KOMODO_DATABASE_USERNAME  $KOMODO_DATABASE_PASSWORD
sqlite  vault      vaultwarden/db.sqlite3                      # a consistent .dump of a live file
path    vaultwarden                                            # files, straight to the repository
exclude db.sqlite3*                                            # the live database: the dump has it
pg      recorder   postgres-homeassistant  $HA_DB_DATABASE_NAME  $HA_DB_USERNAME  optional
```

Paths are under `DATA_DIR` (or `MEDIA_DIR/…`); `$KEY` is any setting; `optional`
makes a missing container or file a note rather than a failure. An exclude without
a `/` matches that name anywhere under the app's paths. `./backup.sh plan` shows
what a node's files add up to. A live database directory is never a `path`: dump
it. Details at the top of [`_lib/backup.sh`](_lib/backup.sh).

## Adding an app

On any node, without touching a script:

1. `stacks/<group>/<app>/docker-compose.yml`, with a name no other app has. Data under
   `${DATA_DIR}/<app>/…`, the node's IP as `${NODE_IP}`, other nodes' as
   `${<NODE>_LAN_IP}` from `fleet.env`. Join the `proxy` network if Traefik fronts it.
2. Whatever it needs of `secrets.conf`, `firewall`, `data-dirs`, `backup`, `config/*.template`.
   A new template's rendered file goes in the root `.gitignore` (a test insists).
3. Add it to `APPS` in the `node.conf` of the node that runs it, where it belongs in
   the bring-up order, and its settings to that node's `local.env.example`.
4. If it has a Traefik route: add its host to Authelia's admin list in
   `identity/authelia/config/configuration.yml.template` if it's admin-only, then
   `./render-configs.sh` and recreate Pi-hole on sieve **and** mochaPot so the name
   resolves. Add a check to `monitoring/gatus/config/config.yaml`.
5. `./setup-secrets.sh`, `sudo ./firewall.sh`, `./compose.sh <app> up -d`, then its
   README's checklist.

`python3 -m unittest discover -s tests` catches the usual slips: a variable nothing
defines, a template that isn't gitignored, an app no node runs, two apps with one name.

## Adding a node

1. A `<NODE>_LAN_IP` line in `fleet.env`, and the node set up with purrbrews-bootstrap
   and this repo's [payload](../payload/README.md). Its MAC is derived from its name.
2. `nodes/<node>/` with the five wrapper scripts copied from any other node,
   `node.conf`, `local.env.example` (with its own `PROXY_SUBNET`) and `README.md`.
3. In its `APPS`: `traefik`, `komodo-periphery` and `scrutiny-collector` as they are.
   They take the node's name from `NODE` and the disk from `DISK_DEVICE`. Its IP goes
   in percolator's `FORWARD_AUTH_CLIENTS`. `TOOLS=(restic)`.
4. An entry in `fleet.json`, and its checks in Gatus.
5. Backups: `sudo ./backup.sh keys`, then its line in the hub's
   `backup/restic/backup.keys` and `repo-setup.sh` and `dump-store-setup.sh` run
   there. The hub's morning check picks the node up by itself.

## Backups

Decided 2026-09-27 (`deprecated/runbook.md`); re-targeted in the 2026-11 rebuild
(`runbook.md`). Every node, every night:

1. **Dumps** its own databases (`pg`, `mongo`, `sqlite` lines) into
   `DUMP_DIR/<node>/<app>/`, each read back before it replaces the last good one;
2. **pushes** them to cellar, the dump store (`DUMP_DIR/<node>/` there), over SSH
   with a key that can only write that one folder;
3. **backs up its files** (`path` lines, plus its own `.env`, `.env.local`,
   every `secrets.env.local` and `/etc/purrbrews`) straight into the restic
   repository, over SFTP, `--host <node> --tag files`.

An app in `APPS` that has never been started on the node is left out, with a
note in the log: the apps come up one at a time, and one that hasn't run has
nothing to back up. The sign is its data folder (or, for an app with only
database lines, its container). Once that exists the app is backed up like the
rest, and a file it needs going missing fails the night. `backup.sh plan`
shows everything, started or not.

The repository lived on roastery; since the 2026-11 rebuild it is on cellar,
the backup hub (`BACKUP_HUB=true` in its `node.conf`), in an SFTP-only account
chrooted to `BACKUP_REPO_ROOT`. cellar reaches it through that account too. The hub backs up the dump store
(`--tag dumps`), prunes, copies the repository to Google Drive and checks each
morning that everything above happened; [backup/restic/README.md](backup/restic/README.md)
has that side and the order to switch it all on.

**Switched on in phase 4** of the [migration plan](../docs/migration-plan.md)
(2026-11-23): the account and the repository on cellar, cellar first.

`BACKUP_REPOSITORY`, `BACKUP_REPO_ROOT`, `DUMP_DIR` and `DUMP_STORE_HOST` are in `fleet.env`; `restic`
is in every node's `TOOLS`, and its `secrets.hook` makes the repository password
on the hub and asks for it everywhere else, plus the ntfy URL for failure alerts.
One key per node (`/root/.ssh/purrbrews-backup`), pinned host keys in `/etc/purrbrews`.

## Updates

Every image is pinned by tag and digest (a test fails otherwise), so nothing
updates on its own, not even an upstream `main` or `latest`. [Dependabot](../.github/dependabot.yml) opens a pull request each Monday
when a pinned image has a new version, one PR per image, after the release has been out a week. Merging changes nothing running:
nodes only fetch `main`, and an app moves when a reviewed commit is checked out
on the node and deployed ([operations](../docs/operations.md)).

- Read the release notes before merging. Pairs that must match arrive as separate
  PRs: Immich server with `ai/immich-ml`, Komodo Core with Periphery (a test
  fails while they differ).
- OpenCloud, Meilisearch, Traccar and Open WebUI migrate their data one way: with
  data there, `compose.sh up` waits for the new version to be acknowledged in
  `.env.local` ([image upgrades](../docs/image-upgrades.md)).
- Database majors (Postgres, Mongo, Redis/Valkey) and OpenCloud majors never come
  as PRs: those need reviewed migration and restore plans, by hand.
- A security fix still waits out the week's cooldown; a critical one is a
  hand-made PR.
- **Old images clean themselves up.** After a successful `up`, `compose.sh` removes the images that app ran before, once nothing
  else uses them. Images shared with another app, or pulled for one not yet
  restarted, stay. Rolling back is pulling the old tag and digest again;
  `PURRBREWS_KEEP_IMAGES=1` keeps them.

## Ingress: a Traefik on every node

Each node runs its own Traefik for its own apps, so a broken proxy or a dead node
only takes down that node's pages. Sign-in is still one SSO, Authelia on percolator.

- **Routes** can be compose labels, a rendered `traefik/config/*.template`, or a
  `traefik/dynamic/*.yml` Go template (sieve's style). Keep every `Host(...)` rule on
  one line in one of those forms: `_lib/dns-records.py` turns each into a Pi-hole
  record pointing at its node.
- **Certificates:** Cloudflare DNS-01. No two nodes may ask for the same set
  (percolator holds the `*.${DOMAIN}` wildcard, the others ask per name), or they
  share Let's Encrypt's five-a-week limit.
- **SSO from another node:** a ForwardAuth middleware calling Authelia **directly**
  on `http://${PERCOLATOR_LAN_IP}:9091/api/authz/forward-auth`, never through
  percolator's Traefik, which drops `X-Forwarded-Method`. The node's IP goes in
  percolator's `FORWARD_AUTH_CLIENTS`, its admin hosts in Authelia's admin rule.
- **A direct port as the way in.** Apps on the smaller nodes keep their own port
  published (LAN only) for when Authelia or Traefik is down. Where the app has no
  login of its own, that's written down in its node's README.

## Conventions

- **Pin image tags**, with the date they were checked in a comment. A floating tag
  needs a written reason (or a line in the node's known gaps).
- **Data outside the repo**, under `${DATA_DIR}`; never a live database directory as
  a backup source, dump it.
- **Hex for generated secrets.** base64's `+ / =` broke an OIDC login once.
- **Publish as little as possible.** Route through Traefik, bind admin-only ports to
  `127.0.0.1`, check `ss -tlnp` first, and put every rule in a `firewall` file.
- **Check auth defaults first.** Note in the app's README whether the image ships a
  default account and how the first login works.
- **Test, don't just parse.** `docker compose config` proves syntax; bring the app up
  and go through its checklist before calling it done.
- **Comments say why.** The how is in the file already; history belongs in the runbook.
