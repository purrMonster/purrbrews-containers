# stacks

One folder per node, one folder per app inside it. Every node works the same way:
the scripts are identical three-line wrappers around [`_lib`](_lib/), and everything
that differs between nodes or apps is a small config file, not code.

```
stacks/
├── fleet.env                  LAN facts every node shares (IPs, gateway, TZ, backups). Committed, not secret
├── _lib/                      the actual scripts (see below)
├── _shared/                   reusable Linux Compose service definitions
└── <node>/
    ├── README.md              role, apps, bring-up order, gotchas
    ├── node.conf              APPS in bring-up order, NETWORK, RESOLVER
    ├── local.env.example      node settings template → .env.local (gitignored)
    ├── scripts/               node-specific tasks and the plan/deploy run.sh
    ├── setup-secrets.sh       wrappers calling ../_lib directly
    ├── render-configs.sh
    ├── compose.sh
    ├── firewall.sh
    ├── backup.sh              Linux shared backup wrapper
    ├── restic/secrets.conf    the backup password and alert URL (cellar: its whole backup hub)
    └── <app>/
        ├── docker-compose.yml
        ├── README.md          first run, "is it working?" (for apps that need one)
        ├── secrets.conf       what setup generates or asks for      (optional)
        ├── firewall           this app's UFW rules                  (optional)
        ├── data-dirs          directories created before `up`       (optional)
        ├── backup             what gets dumped and backed up         (optional)
        ├── prepare.sh         run before `up`                       (optional)
        └── config/*.template  rendered next to themselves           (optional)
```

| Node | Role | |
|---|---|---|
| `sieve` | Network: DNS, DHCP, tunnel, alerting | [sieve/](sieve/README.md) |
| `percolator` | Ingress, identity (SSO) and the daily apps | [percolator/](percolator/README.md) |
| `cellar` | Backups, file shares, Komodo, the Scrutiny hub | [cellar/](cellar/README.md) |
| `mochaPot` | Home automation, music, the wall screen, secondary DNS | [mochaPot/](mochaPot/README.md) |
| `grinder` | Automation, AI indexing, self-tracking | [grinder/](grinder/README.md) |
| `roastery`* | Windows workstation: GPU for Immich ML and the local LLMs (llama-swap) | [roastery/](roastery/README.md) |

\* roastery uses [`init/roastery-init.ps1`](../init/roastery-init.ps1) for its
Windows rebuild. It has no `/opt/purrbrews/.env` or `DATA_DIR`. PowerShell twins
of the stack scripts (`*.ps1`) let it run without WSL.

## The shared scripts

Run `bash scripts/run.sh` as the ops user to preview the plan. To execute, pass
`--release <full-commit-id> --acknowledge-prerequisites`: setup/render, firewall,
then each selected app in `node.conf` order, waiting for Compose readiness.
See [operations](../docs/operations.md) for release controls and optional apps. First-time per-app workflows with manual checkpoints should still follow
the node README. Backup, DHCP handover, kiosk setup and recovery tasks keep their
separate commands. The individual entry points remain available from the node root.

| Script | Does |
|---|---|
| `scripts/run.sh` | Plan by default; explicit reviewed revision executes setup → firewall → Compose. Stops on failure |
| `./setup-secrets.sh` | First-time setup and re-run after a pull: adds new `.env.local` keys, migrates renamed keys, creates each app's secrets, then renders. Existing values stay unchanged |
| `./render-configs.sh` | Renders each `*.template` beside its source; refuses missing values and preserves the last good output |
| `./compose.sh <app> …` | Compose with the right env files and startup checks. `--all` follows `node.conf` order (reverse for teardown); `--list` reports unlisted app folders |
| `sudo ./firewall.sh` | Applies UFW rules from app `firewall` files; `--dry-run` previews them |
| `sudo ./backup.sh <cmd>` | Runs node backups from app `backup` files: `plan`, `doctor`, `keys`, `nightly`, `restic …`. See [Backups](#backups) |

**Env files, later ones win:** `stacks/fleet.env` → `/opt/purrbrews/.env` (written by
init: `NODE`, `NODE_IP`, `PUID`/`PGID`, `DATA_DIR`, `MEDIA_DIR`) → the node's
`.env.local` → the app's `secrets.env.local`. The renderer and compose see exactly
the same values.

### Where shared behavior lives

Keep the small node wrappers: they pass their own directory to `_lib`. Change
shared behavior here, and keep differences between nodes in `node.conf` or the
app's files. The app files are discovered by location, so identical files can
still be required on several nodes.

| Helper | Responsibility |
|---|---|
| [`_lib/common.sh`](_lib/common.sh) | Node discovery, env precedence, key migration and Docker invocation |
| [`_lib/purrbrews.ps1`](_lib/purrbrews.ps1) | Windows counterparts for setup, rendering and Compose |
| [`_lib/secrets.sh`](_lib/secrets.sh) | The `secrets.conf` format and secret generation |
| [`_lib/render-template.py`](_lib/render-template.py) | Template substitution and atomic output on Linux |
| [`_lib/check-compose-config.py`](_lib/check-compose-config.py) | Refuse unresolved placeholders without printing values |
| [`_lib/dns-records.py`](_lib/dns-records.py) | Shared route discovery and Pi-hole record generation |
| [`_lib/restic-env.sh`](_lib/restic-env.sh) | Backup transport, repository environment and reachability |

The PowerShell implementation deliberately mirrors the shell helpers. Changes
to their shared contract need to account for both platforms.

### Shared service definitions

Komodo Periphery and Scrutiny collectors on grinder, mochaPot, percolator and
sieve extend [`_shared/`](_shared/README.md). Change shared settings once there;
keep keys, disk devices and other local paths in each app's Compose file. The
full repository must be present when deploying; an app folder alone is not enough.

### Find and inspect an app

From the node folder, `./compose.sh --help` and `./compose.sh --list` need no
Docker daemon or secrets. On Windows use `.\compose.ps1 --help` and
`.\compose.ps1 --list`. The list follows `node.conf` and flags extra Compose folders.

Use `./compose.sh <app> ps` for state and `./compose.sh <app> config --quiet`
for Compose's configuration check when the node is ready. The Linux wrapper
does not migrate environment keys or create networks for these commands. Those
preparations happen for `up`, `create`, `start`, `restart`, `run`, `watch` and `scale`.
Both wrappers recognize separate values for
[Compose global options](https://docs.docker.com/reference/cli/docker/compose/#options)
such as `--profile` and `--project-name`, so those values do not affect command
selection or reverse the app order accidentally.

Put global preview options before the command: `./compose.sh <app> --dry-run up`
(or `.\compose.ps1 <app> --dry-run up`). The wrappers forward the preview to
Compose without migrating keys, creating networks or running startup preflight.
Preview requires existing inputs; it does not create missing directories or renders.
Windows startup also rejects renders older than their template or environment inputs.

See [the offline test guide](../tests/README.md) before changing shared helpers.

### Files used without a literal caller

These are the discovery contracts. Preserve the filename and location when
adding an app; a search for an exact filename alone cannot establish usage.

| Input | Consumer |
|---|---|
| `node.conf` / `APPS` | Compose execution order; reverse order for teardown |
| `<app>/docker-compose.yml` | Compose entry point and app discovery; may extend `_shared/` |
| `<app>/secrets.conf` | `secrets.sh` during setup, including non-Compose apps such as restic |
| `<app>/data-dirs`, `<app>/prepare.sh` | Linux Compose preflight |
| `*.template` below a node | Render helpers; output goes beside its template |
| `<app>/firewall`, `<app>/backup` | Shared firewall and backup helpers |
| `restic/*.service`, `restic/*.timer` | `backup.sh`'s `node_units()` installation and timer discovery |
| Init's ordered step list | `step_<name>` in Bash, `Step-<name>` in PowerShell |

Archived files under root `Deprecated/` are outside these deployment discovery
paths and excluded from the active Graphify map. Existing source checks exclude
archives for syntax and current references, but the credential scan includes them.

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
NEXTCLOUD_OIDC_CLIENT_SECRET_HASH hash pbkdf2 nextcloud:NEXTCLOUD_OIDC_CLIENT_SECRET
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
pg      nextcloud  nextcloud-postgres  nextcloud  nextcloud   # pg_dump inside the app's own container
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

1. `stacks/<node>/<app>/docker-compose.yml`. Data under `${DATA_DIR}/<app>/…`, the
   node's IP as `${NODE_IP}`, other nodes' as `${<NODE>_LAN_IP}` from `fleet.env`. Join
   the node's network (`NETWORK` in `node.conf`) if Traefik fronts it.
2. Whatever it needs of `secrets.conf`, `firewall`, `data-dirs`, `backup`, `config/*.template`.
   A new template's rendered file goes in the root `.gitignore` (a test insists).
3. Add it to `APPS` in `node.conf`, where it belongs in the bring-up order.
4. If it has a Traefik route: add its host to Authelia's admin list in
   `percolator/authelia/config/configuration.yml.template` if it's admin-only, then
   `./render-configs.sh` and `./compose.sh pihole up -d` on sieve **and** mochaPot so
   the name resolves. Add a check to `sieve/gatus/config/config.yaml`.
5. `./setup-secrets.sh`, `sudo ./firewall.sh`, `./compose.sh <app> up -d`, then its
   README's checklist.

`python3 -m unittest discover -s tests` catches the usual slips: a variable nothing
defines, a template that isn't gitignored, an app folder missing from `node.conf`.

## Adding a node

1. Its name and IP in `NODE_IPS` (`init/purrbrews-init.env.example` and the real one on
   roastery) and a `<NODE>_LAN_IP` line in `fleet.env`.
2. `stacks/<node>/` with the wrapper scripts copied from any other node (five on
   Linux, with `backup.sh`), `node.conf`, `local.env.example`, `README.md`, and
   `restic/secrets.conf` copied from grinder's.
3. Its own `traefik/` (copy mochaPot's or grinder's), and its IP in percolator's
   `FORWARD_AUTH_CLIENTS`.
4. `komodo-periphery/` and `scrutiny-collector/` copied as they are: they take the
   node's name from `NODE` and the disk from `DISK_DEVICE`.
5. Its checks in Gatus.
6. Backups: `sudo ./backup.sh keys`, then its lines in roastery's
   `backup-target/authorized_keys` and cellar's `restic/dump-store.keys`, and
   `setup.ps1` on roastery again (its firewall rule reads the addresses from
   `fleet.env`). cellar's morning check picks the node up by itself.

## Backups

Decided 2026-09-27 (runbook). Every node, every night:

1. **Dumps** its own databases (`pg`, `mongo`, `sqlite` lines) into
   `DUMP_DIR/<node>/<app>/`, each read back before it replaces the last good one;
2. **pushes** them to cellar, the dump store (`DUMP_DIR/<node>/` there), over SSH
   with a key that can only write that one folder;
3. **backs up its files** (`path` lines, plus its own `.env`, `.env.local`,
   every `secrets.env.local` and `/etc/purrbrews`) straight into the restic
   repository on roastery, over SFTP (through rclone: Windows' sftp-server refuses
   restic's chmod), `--host <node> --tag files`.

cellar backs up the dump store (`--tag dumps`), wakes roastery, prunes, copies the
repository to Google Drive and checks each morning that everything above happened;
[cellar/restic/README.md](cellar/restic/README.md) has that side and the order to
switch it all on. roastery holds the repository on its NVMe
([roastery/README.md](roastery/README.md#backup-target)).

`BACKUP_REPOSITORY`, `DUMP_DIR` and `DUMP_STORE_HOST` are in `fleet.env`; each
node's `restic/secrets.conf` asks for the repository password (the same
everywhere, made on cellar) and the ntfy URL for failure alerts. One key per
node (`/root/.ssh/purrbrews-backup`), pinned host keys in `/etc/purrbrews`.

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
