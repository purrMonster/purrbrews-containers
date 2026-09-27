# Remote access: Tailscale

SSH to every node and Remote Desktop to roastery, from anywhere, with **no port
open on the router**. Every machine runs its own Tailscale client (decided
2026-09-27 over a single subnet router: see the runbook), so each one has its own
tailnet address, name and rules.

| What | Where | Who can reach it over the tailnet |
|---|---|---|
| `ssh barista@sieve` … `ssh barista@grinder` | the five nodes, `tag:purrbrews-node` | tailnet admins (you), port 22 only |
| `mstsc /v:roastery` | roastery, joined as you | your own devices, port 3389 only |

Nothing else answers over the tailnet: not the web apps, not Authelia, not
Pi-hole, not the backup SFTP. The tailnet is a way in for an admin, not a second
LAN.

## Two gates, and why both

1. **The tailnet policy**, [`policy.hujson`](policy.hujson): who may send what to
   whom. Nodes are tagged, can receive SSH from admins, and can't start anything
   themselves, so a compromised node can't reach your laptop through the tailnet.
2. **UFW on each node**, as before. Tailscale's default is to put its own firewall
   chains ahead of UFW's and accept everything arriving on `tailscale0`, which would
   quietly open every port on the node to anyone the policy lets in. init runs it
   with `--netfilter-mode=off`, and UFW allows exactly two things: `22/tcp in on
   tailscale0` and `41641/udp` (WireGuard itself). Published container ports stay
   shut as well: ufw-docker only lets Docker's own subnets past (runbook,
   2026-09-26).

Nodes also run `--accept-dns=false`, so they keep resolving through Pi-hole,
and Tailscale's auto-update is on, since unattended-upgrades only takes Debian's
security fixes.

## Setting it up, in this order

**1. Tailnet, once** (admin console, <https://login.tailscale.com/admin>):

- Sign up with the account that should own the tailnet. That account is the admin.
- *Access controls* → JSON editor → paste [`policy.hujson`](policy.hujson) → Save.
  This replaces Tailscale's default allow-all. **Do this before any node joins**,
  or init's `--advertise-tags` is refused.
- *DNS* → MagicDNS on, so `sieve` resolves to its tailnet address on your laptop.

**2. Your laptop and phone:** install Tailscale, sign in with the same account.
The laptop's SSH public key must be in `bootstrap/data/authorized_keys` on
roastery like any other key; the nodes pick it up within the hour.

**3. Each node** (sudo is yours; one node at a time, at a terminal):

```bash
cd /opt/purrbrews && git pull --ff-only          # or wait for the daily pull
sudo bash init/purrbrews-init.sh --only tailscale
```

It installs Tailscale from its apt repo, adds the two UFW rules, then prints a
login link: open it, sign in as the admin, done. New nodes get the same step as
part of a normal init run. To skip the link, put a one-off, pre-authorized,
tagged auth key in `/etc/purrbrews/tailscale-authkey` (root, 0600) first; the
step uses it once and deletes it. Never put a key in `purrbrews-init.env`: it's
served openly, and init and the bootstrap container both refuse one.

**4. roastery** (elevated PowerShell):

```powershell
.\stacks\roastery\remote-access\setup.ps1
```

Then in the admin console, *Machines → roastery → Disable key expiry* (it's
joined as you, not tagged, so its key would lapse after 180 days). Details in
[`stacks/roastery/README.md`](../stacks/roastery/README.md#remote-access).

## Is it working?

Check from outside the house (phone hotspot), and tick the runbook only on what
you actually saw:

- `tailscale status` on the laptop lists all six machines; the nodes show
  `tag:purrbrews-node`, roastery shows your account.
- `ssh barista@<node>` works for all five, and `tailscale status` shows the
  connection as `direct` rather than `relay` (relay still works, just slower).
- A port that must stay closed is closed over the tailnet, e.g. from the laptop:
  `nc -zv -w3 percolator 443` and `nc -zv -w3 sieve 8080` both time out.
- `mstsc /v:roastery` opens a session, after waking it through cellar if it was
  asleep.
- On a node, `sudo ufw status | grep tailscale0` shows the one SSH rule, and
  `sudo nft list ruleset | grep -c 'ts-'` prints 0 (no Tailscale chains, in
  either iptables or nftables form).

## Day 2

- **Revoke a device:** admin console → *Machines* → the device → *Remove*. For a
  lost laptop, also delete its SSH key from `bootstrap/data/authorized_keys`.
- **Re-run the step** after changing `TAILSCALE_TAGS` or if a node was removed:
  `sudo bash init/purrbrews-init.sh --only tailscale`. It restates the whole
  configuration each time (`--reset`).
- **roastery asleep:** `ssh barista@cellar`, then
  `/opt/purrbrews/stacks/cellar/restic/wake-roastery.sh`.

## Not done here (on purpose, for now)

- **Web apps from outside.** The `*.${DOMAIN}` names resolve to LAN addresses, and
  UFW keeps 443 closed to the tailnet. Opening that up is a separate decision
  (split DNS to Pi-hole plus 443 on `tailscale0`, behind Authelia as now).
- **Cloud VMs.** Join them with their own tag (say `tag:cloud`) and give that tag
  its own narrow grants in the policy; nothing about the nodes changes.
- **Headscale.** If the Tailscale-run control server ever bothers you, the
  clients can point at a self-hosted Headscale (`--login-server`); that needs a
  small public VPS, so it waits.
