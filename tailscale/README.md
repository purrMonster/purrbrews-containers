# Remote access: Tailscale

SSH to every node and Remote Desktop to roastery, from anywhere, with **no port
open on the router**. Every machine runs its own Tailscale client (decided
2026-09-27 over a single subnet router: see the runbook), so each one has its own
tailnet address, name and rules.

| What | Where | Who can reach it over the tailnet |
|---|---|---|
| `ssh barista@sieve` … `ssh barista@grinder` | the five nodes, `tag:purrbrews-node` | tailnet admins (you), port 22 only |
| `mstsc /v:roastery` | roastery, joined as you | your own devices, port 3389 only |
| `https://<app>.${DOMAIN}`, every app, admin pages too | the nodes' Traefik, through cellar or grinder | your devices, 443 only; Authelia still decides who sees what |

Nothing else answers over the tailnet: not the backdoor ports (`:8123`, `:5678`…),
not the backup SFTP, not the rest of the LAN.

## Apps over the tailnet

The app names work the same away from home as at home, with the same valid
certificates and the same Authelia login:

- **cellar and grinder are subnet routers** (`TAILSCALE_SUBNET_ROUTERS`). They
  advertise `192.168.0.0/23`, and forward only web (443) and DNS (53) onto the LAN,
  NATed, so every node sees them as an ordinary LAN client and its existing
  firewall rules apply unchanged. Two of them, so either can be down.
- **Why a /23 when the house is a /24:** a device picks the most specific route.
  At home your laptop's own `/24` beats the tailnet's `/23`, so it keeps talking to
  the LAN directly, SSH to LAN addresses included. Away, only the `/23` exists, so
  the traffic goes through the tailnet.
- **The policy names exactly what's reachable:** the six Traefik hosts (the nodes
  and roastery) on 443, and the two Pi-holes on 53.
- **Split DNS:** Tailscale sends lookups for `${DOMAIN}` to the Pi-holes, which
  answer with the LAN addresses the routers carry you to.

Two things to know:

- Away from home on a network that is itself `192.168.0.x` or `192.168.1.x` (common
  in homes and cafés), that network's own route wins and the app names won't load.
  `ssh barista@<node>` still works (it uses tailnet addresses).
- Linux clients need `tailscale up --accept-routes`; macOS, Windows, iOS and Android
  accept routes by default.

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
- *DNS* → *Add nameserver* → *Custom* → `192.168.0.10`, tick *Restrict to domain*,
  enter your domain. Again with `192.168.0.13`. That's the split DNS; it can't be
  set from the policy file.

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
  `nc -zv -w3 percolator 443` (its tailnet address) and `nc -zv -w3 sieve 8080`
  both time out.
- Away from home: `https://immich.<domain>` and an admin page such as
  `https://pihole.<domain>` load after the Authelia login, and
  `nc -zv -w3 192.168.0.13 8123` (a backdoor port) times out.
- Admin console → *Machines*: cellar and grinder show *Subnets* `192.168.0.0/23`,
  approved. On each, `systemctl is-active purrbrews-tailscale-nat` says `active`.
- `mstsc /v:roastery` opens a session, after waking it through cellar if it was
  asleep.
- On a node, `sudo ufw status | grep tailscale0` shows the SSH rule (plus the three
  forwarding rules on cellar and grinder), and
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

- **The internet at large.** Apps for people without Tailscale go through
  Cloudflare Tunnel instead (`stacks/sieve/cloudflared/`), admin pages never.
- **Cloud VMs.** Join them with their own tag (say `tag:cloud`) and give that tag
  its own narrow grants in the policy; nothing about the nodes changes.
- **Headscale.** If the Tailscale-run control server ever bothers you, the
  clients can point at a self-hosted Headscale (`--login-server`); that needs a
  small public VPS, so it waits.
