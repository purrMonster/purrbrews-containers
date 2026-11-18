# payload

What [purrbrews-bootstrap](https://github.com/purrMonster/purrbrews-bootstrap)
runs on a new machine, after its own steps, to make it a fleet node. It replaces
the part of the old `init/purrbrews-init.sh` that purrbrews-bootstrap doesn't do
(`deprecated/init/`, `docs/carry-over-map.md`).

| purrbrews-bootstrap does | this payload does (`purrbrews-node.sh`) |
|---|---|
| hostname (`--hostname`), timezone, packages, the ops user with a sudo password, SSH keys and their hourly sync, key-only SSH, no sleep, journald, Docker, UFW with ufw-docker | clones this repo to `/opt/purrbrews`, writes `/opt/purrbrews/.env` (`NODE`, `NODE_IP`, `TZ`, `PUID`/`PGID`, the folders), makes `/srv/data` and `/srv/media`, lists the other nodes in `/etc/hosts`, installs the daily fetch timer, and last gives the wired interface its static address and fixed MAC |

Node addresses, gateway, LAN and timezone come from `stacks/fleet.env` in the
checkout it makes, so they have one source. MACs are derived from each node's
name (`lib/node-mac.sh`), the same ones the old fleet used;
`bash scripts/fleet-macs.sh` lists them, and the Pi-holes' static leases come
from the same list.

## Serving it (on americano)

Deployment copies on americano live in `~/Desktop/Tools`, apart from the
development checkouts in `~/Desktop/Projects` (owner, 2026-11-19).

1. A checkout of this repo, on `main` and only ever pulled:
   `~/Desktop/Tools/purrbrews-containers`. `git pull` there is how a new payload
   reaches the next machine; no restart needed.
2. purrbrews-bootstrap in `~/Desktop/Tools/purrbrews-bootstrap`, its `.env` with
   `BOOTSTRAP_PAYLOAD=$HOME/Desktop/Tools/purrbrews-containers/payload` and
   `BOOTSTRAP_PUBLIC_URL=https://<americano's reserved address>:8443`, then
   `docker compose up -d`. Docker needs macOS's *Files and Folders → Desktop
   Folder* permission, or the payload looks empty. Check:
   `curl -sk https://localhost:8443/files/SHA256SUMS` lists the files.
3. On its admin page, **Settings → Payload entry script**: `purrbrews-node.sh`.
4. In `client/bootstrap.sh`'s settings block on americano: `TIMEZONE="Asia/Kolkata"`.

Everything in this folder is served to anyone on the LAN who asks. Nothing
secret goes in it: no tokens, no ping URLs, not the real domain.

## Making a node

Debian 13 netinst with the SSH server, plugged in by wire (a USB Ethernet
adapter on the x360s). Then, at its console or over SSH, the one-liner from
the admin page with the node's name on the end:

```bash
curl -fsSk https://<americano>:8443/bootstrap.sh | sudo PB_PIN='sha256//…' bash -s -- \
  --user barista --hostname sieve -- sieve
```

- **Name:** what follows the second `--` is the node, a folder under `nodes/`.
- **Network change:** the payload asks on the terminal before it changes the
  network. The switch then runs detached and rolls itself back in about a
  minute if the gateway doesn't answer. Over SSH, reconnect to `barista@<its new address>`.
- **Unattended:** add `--yes` after the node name to skip the question.

Then, as barista and not with sudo, in `/opt/purrbrews/nodes/<node>`:
`./setup-secrets.sh`, then that node's README.

## Running it again

Every step can be run again. A re-run fetches the repo but never moves the
checkout: moving it is a reviewed step (`docs/operations.md`). To repeat one
step, add its name after the node, for example `-- sieve --only network --yes`.
Steps: `packages repo node folders hosts timers tailnet network`; `tailnet`
runs only when named (below).

## Joining the tailnet

Phase 10 of `docs/migration-plan.md`, once every node is up and the policy is in
the admin console ([`tailscale/README.md`](../tailscale/README.md)). The same
one-liner, with the step named:

```bash
curl -fsSk https://<americano>:8443/bootstrap.sh | sudo PB_PIN='sha256//…' bash -s -- \
  --user barista -- sieve --only tailnet
```

It installs Tailscale from its apt repo, opens SSH on `tailscale0` in UFW, and
joins with `tag:purrbrews-node`, printing a sign-in link (open it, sign in as
the tailnet's admin). On cellar and grinder, the subnet routers, it also
forwards web and DNS onto the LAN. A one-off auth key in
`/etc/purrbrews/tailscale-authkey` (root, 600) skips the link; it's used once
and deleted. Never put a key in `payload.env`: it's served openly.

## What it doesn't do

- Backups: `sudo ./backup.sh install` on the node, once the hub exists (phase 5).
- Anything as root from the checkout. The checkout belongs to the ops user, so
  root runs only the verified files of this payload, and only reads data from
  the checkout. A test checks this.

## Not tested on a machine yet

The steps that change the system for good (`packages`, `timers`, `network`)
haven't run on real hardware. The tests run `repo`, `node`, `folders` and
`hosts` as root against a throwaway checkout, and check the rest by reading
the script. The network switch is the old init's, unchanged in substance,
and it ran on all five nodes in 2026-10.
