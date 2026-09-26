# stacks

One folder per node, one folder per app inside it. Every node works the same way:
the scripts are identical three-line wrappers around [`_lib`](_lib/), and everything
that differs between nodes or apps is a small config file, not code.

```
stacks/
├── fleet.env                  LAN facts every node shares (IPs, gateway, TZ). Committed, not secret
├── _lib/                      the actual scripts (see below)
└── <node>/
    ├── README.md              role, apps, bring-up order, gotchas
    ├── node.conf              APPS in bring-up order, NETWORK, RESOLVER
    ├── local.env.example      node settings template → .env.local (gitignored)
    ├── setup-secrets.sh       ┐
    ├── render-configs.sh      │ the same wrapper on every node:
    ├── compose.sh             │ exec ../_lib/<script> <this dir> "$@"
    ├── firewall.sh            ┘
    └── <app>/
        ├── docker-compose.yml
        ├── README.md          first run, "is it working?" (for apps that need one)
        ├── secrets.conf       what setup generates or asks for      (optional)
        ├── firewall           this app's UFW rules                  (optional)
        ├── data-dirs          directories created before `up`       (optional)
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
| `roastery`* | Windows workstation: GPU for Immich ML and Ollama | [roastery/](roastery/README.md) |

\* Not a fleet node: no init, no `/opt/purrbrews/.env`, no `DATA_DIR`. It has
PowerShell twins of the scripts (`*.ps1`) so it doesn't need WSL.

## The shared scripts

Run them from the node's folder, as the ops user, never with sudo (they sudo the
few commands that need it; root-owned secrets files break the next run).

| Script | Does |
|---|---|
| `./setup-secrets.sh` | First-time setup, and the thing to re-run after a pull. `.env.local` from `local.env.example` (new keys appended, [renamed keys](_lib/renamed-keys) copied across), a prompt for every `REPLACE_ME`, every app's `secrets.conf`, then render. Never changes a value that's already set |
| `./render-configs.sh` | Every `*.template` → the file beside it. A template with an unset or `REPLACE_ME` variable fails and its last good render stays. On a node with `RESOLVER` set, regenerates the Pi-hole records first |
| `./compose.sh <app> …` | `docker compose` with the env files. Before `up` it checks renders are current, creates `data-dirs`, runs `prepare.sh`, and refuses a resolved config with a `REPLACE_ME` left in it. `--all` goes in `node.conf` order (backwards for `down`); `--list` also shows app folders `node.conf` doesn't mention |
| `sudo ./firewall.sh` | UFW rules from every app's `firewall` file; `--dry-run` prints them |

**Env files, later ones win:** `stacks/fleet.env` → `/opt/purrbrews/.env` (written by
init: `NODE`, `NODE_IP`, `PUID`/`PGID`, `DATA_DIR`, `MEDIA_DIR`) → the node's
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

### data-dirs

```
paperless/consume PUID:PGID 2775
MEDIA_DIR/household PUID:PGID 755
```

Created before `up` if missing, never touched after. Without it Docker creates a
bind-mount source as `root:root`, and an image that runs as a fixed user crash-loops.

## Adding an app

On any node, without touching a script:

1. `stacks/<node>/<app>/docker-compose.yml`. Data under `${DATA_DIR}/<app>/…`, the
   node's IP as `${NODE_IP}`, other nodes' as `${<NODE>_LAN_IP}` from `fleet.env`. Join
   the node's network (`NETWORK` in `node.conf`) if Traefik fronts it.
2. Whatever it needs of `secrets.conf`, `firewall`, `data-dirs`, `config/*.template`.
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
2. `stacks/<node>/` with the four wrapper scripts copied from any other node,
   `node.conf`, `local.env.example`, `README.md`.
3. Its own `traefik/` (copy mochaPot's or grinder's), and its IP in percolator's
   `FORWARD_AUTH_CLIENTS`.
4. `komodo-periphery/` and `scrutiny-collector/` copied as they are: they take the
   node's name from `NODE` and the disk from `DISK_DEVICE`.
5. Its checks in Gatus.

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
