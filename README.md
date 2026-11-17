# purrbrews-containers

**A self-hosted home server fleet, written down as code.**

purrBrews is a small, multi-node home lab that replaces everyday cloud services
(photos, files, passwords, documents, recipes, budgets, home automation) with
ones that run at home. This repository holds the Docker Compose stacks, the
scripts that run them the same way on every machine, and the record of why
things are the way they are.

> **Being rebuilt (November 2026).** The fleet moved house, lost its GPU
> workstation, and is being brought back up on a new network with the repo
> reorganised by stack instead of by node. The code here passes its offline
> tests but has not run on a machine since the move.
> [`docs/migration-plan.md`](docs/migration-plan.md) is the order of work;
> [`runbook.md`](runbook.md) has the decisions and what is still open. The
> fleet as it was is under [`deprecated/`](deprecated/ABOUT.md) and at tag
> `freeze-2026-10`.

## How it fits together

```
stacks/<group>/<app>/     one folder per app, wherever it runs
nodes/<node>/             one small folder per machine: which apps, in what order, its settings
stacks/_lib/              the scripts every node shares
stacks/fleet.env          the house network: addresses, gateway, where backups go
```

A node is a list. `nodes/grinder/node.conf` says `APPS=(… litellm openwebui …)`,
the shared scripts find each app's folder by name, and every node runs the same
three commands from its own folder:

```bash
./setup-secrets.sh          # settings, secrets, rendered configs; safe to re-run
sudo ./firewall.sh
./compose.sh --all up -d    # or one app at a time, in the node README's order
```

Secrets are generated on the node and never leave it. Moving an app to another
machine is moving one word between two `node.conf` files.

## The fleet

Nodes are named after coffee gear. Hardware and rooms: [`docs/hardware.md`](docs/hardware.md).

| Node | Address | Machine | Role |
|---|---|---|---|
| [`sieve`](nodes/sieve/README.md) | 192.168.1.10 | ThinkCentre, by the router | Pi-hole DNS and DHCP, Unbound, the Cloudflare tunnel, ntfy, Gatus |
| [`percolator`](nodes/percolator/README.md) | 192.168.1.11 | ThinkCentre | Traefik, CrowdSec, LLDAP, Authelia, and the household apps (Vaultwarden, OpenCloud, Radicale, Immich, Paperless-ngx, Mealie, Vikunja, Actual Budget, FreshRSS, meowGram) |
| [`cellar`](nodes/cellar/README.md) | 192.168.1.12 | ThinkCentre | Backups and their repository, Komodo, the Scrutiny hub |
| [`mochaPot`](nodes/mochaPot/README.md) | 192.168.1.13 | Laptop with a touchscreen | Home Assistant, Music Assistant, the second Pi-hole, the wall screen |
| [`grinder`](nodes/grinder/README.md) | 192.168.1.14 | Bare laptop board | n8n, pgvector, LiteLLM (a cloud model behind one address), Open WebUI, Immich's machine learning, Karakeep, FitTrackee, Traccar, ESPHome |

Every node also runs its own Traefik, a Komodo agent and a Scrutiny collector.

## Repository layout

```
stacks/                     the apps, by group: network, identity, mail, apps, home,
                            automation, ai, monitoring, fleet-management, backup
nodes/                      node.conf, local.env.example and the wrapper scripts, per machine
scripts/                    fleet.py (plan and deploy a reviewed commit), images.py (digests),
                            fleet-macs.sh (each node's address and MAC)
payload/                    what purrbrews-bootstrap runs to make a fresh machine a node
fleet.json                  each node's tier, optional apps and prerequisites
tailscale/                  remote access: the tailnet policy
runbook.md                  dated decisions and the backlog: the why, not just the what
docs/                       start at docs/MAP.md
tests/                      offline checks: python3 -m unittest discover -s tests
deprecated/                 the fleet before the rebuild, kept as it was
```

[`stacks/README.md`](stacks/README.md) has the details: the file each app can
have, how to add an app or a node, how backups and updates work.

A fresh machine becomes a node with
[purrbrews-bootstrap](https://github.com/purrMonster/purrbrews-bootstrap), a
separate small server that hands out SSH keys and sets up a new Debian install,
and then runs this repo's [`payload/`](payload/README.md): the checkout, the
node's settings, its static address and fixed MAC.

## Design principles

- **Public by design.** This repo is public and nodes clone it anonymously.
  Nothing secret is ever committed: no passwords, tokens, keys or hashes, not
  even encrypted, and not the real domain. `*.example` and `*.template` files
  carry placeholders.
- **Secrets are born on the node.** `setup-secrets.sh` reads each app's
  `secrets.conf` and writes real values into gitignored files there.
- **Idempotent everything.** Every script checks before it changes. Re-running
  is the supported way to repair or update.
- **One home per app, the same scripts everywhere.** What differs between
  machines is a setting in `node.conf`, never a fork of a script or a copy of
  a compose file.
- **Small blast radius.** Each node has its own Traefik for its own apps; only
  the login (Authelia on percolator) is shared.
- **Pinned and reviewed.** Every image is pinned by tag and digest. Nodes fetch
  `main` but never pull it: a reviewed commit is deployed by hand
  ([operations](docs/operations.md)).
- **Written down.** Decisions go in the runbook with their reasons, so whoever
  fixes something at midnight knows why it is the way it is.

## Working on it

Read [`AGENTS.md`](AGENTS.md) first if you are an AI agent: it sets what may be
changed, pushed or touched on a node without asking.

```bash
python3 -m unittest discover -s tests      # or: python3 -m pytest tests
python3 scripts/fleet.py validate
```
