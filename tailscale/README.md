# Remote access: Tailscale

SSH to every node, and the apps by their usual names, from anywhere, with **no
port open on the router**. Every node runs its own Tailscale client (decided
2026-09-27 over a single subnet router; `deprecated/runbook.md`), so each one has
its own tailnet address, name and rules. Joining is the payload's `tailnet` step
(W5, 2026-11-18), brought up in phase 10 of the
[migration plan](../docs/migration-plan.md).

| What | Where | Who can reach it over the tailnet |
|---|---|---|
| `ssh barista@sieve` … `ssh barista@grinder` | the five nodes, `tag:purrbrews-node` | tailnet admins (you), port 22 only |
| `https://<app>.${DOMAIN}`, every app, admin pages too | the nodes' Traefik, through cellar or grinder | your devices, 443 only; Authelia still decides who sees what |

Nothing else answers over the tailnet: not the direct ports (`:8123`, `:5678`…),
not the backup SFTP, not the voice ports, not the rest of the LAN.

## Apps over the tailnet

The app names work the same away from home as at home, with the same valid
certificates and the same Authelia login:

- **cellar and grinder are subnet routers** (`TAILSCALE_SUBNET_ROUTERS` in
  `payload/payload.env`). They advertise `192.168.0.0/23` and forward only web
  (443) and DNS (53) onto the LAN, NATed, so every node sees them as an ordinary
  LAN client and its existing firewall rules apply unchanged. Two of them, so
  either can be down.
- **Why a /23 when the house is a /24:** a device picks the most specific route.
  At home your laptop's own `192.168.1.0/24` beats the tailnet's `/23`, so it
  keeps talking to the LAN directly, SSH to LAN addresses included. Away, only
  the `/23` exists, so the traffic goes through the tailnet. A /23 has to start
  on an even third number, so the one around `192.168.1.x` is `192.168.0.0/23`.
- **The policy names exactly what's reachable:** the five Traefik hosts (the
  nodes) on 443, and the two Pi-holes on 53.
- **Split DNS:** Tailscale sends lookups for `${DOMAIN}` to the Pi-holes, which
  answer with the LAN addresses the routers carry you to.

Two things to know:

- Away from home on a network that is itself `192.168.0.x` or `192.168.1.x`
  (common in homes and cafés), that network's own route wins and the app names
  won't load. `ssh barista@<node>` still works (it uses tailnet addresses).
- Linux clients need `tailscale up --accept-routes`; macOS, Windows, iOS and Android
  accept routes by default.

## Two gates, and why both

1. **The tailnet policy**, [`policy.hujson`](policy.hujson): who may send what to
   whom. Nodes are tagged, can receive SSH from admins, and can't start anything
   themselves, so a compromised node can't reach your laptop through the tailnet.
2. **UFW on each node**, as before. Tailscale's default is to put its own firewall
   chains ahead of UFW's and accept everything arriving on `tailscale0`, which would
   quietly open every port on the node to anyone the policy lets in. The `tailnet`
   step runs it with `--netfilter-mode=off`, and UFW allows exactly two things:
   `22/tcp in on tailscale0` and `41641/udp` (WireGuard itself). Published
   container ports stay shut as well: ufw-docker only lets Docker's own subnets
   past.

Nodes also run `--accept-dns=false`, so they keep resolving through the
Pi-holes, and Tailscale's auto-update is on, since Debian's unattended upgrades
don't cover Tailscale's own repo.

## Setting it up, in this order

**1. Tailnet, once** (admin console, <https://login.tailscale.com/admin>):

- Sign up with the account that should own the tailnet. That account is the admin.
- *Access controls* → JSON editor → paste [`policy.hujson`](policy.hujson) → Save.
  This replaces Tailscale's default allow-all. **Do this before any node joins**,
  or the step's `--advertise-tags` is refused.
- *DNS* → MagicDNS on, so `sieve` resolves to its tailnet address on your laptop.
- *DNS* → *Add nameserver* → *Custom* → `192.168.1.10`, tick *Restrict to domain*,
  enter your domain. Again with `192.168.1.13`. That's the split DNS; it can't be
  set from the policy file.

**2. americano and the phone:** install Tailscale, sign in with the same account.
americano's SSH key is already the one the nodes trust (purrbrews-bootstrap
put it there); a new device's key goes in through purrbrews-bootstrap the same
way.

**3. Each node**, one at a time, from a terminal (so the sign-in link can show):
the bootstrap one-liner with the step named (`payload/README.md`, "Joining the
tailnet"):

```bash
curl -fsSk https://<americano>:8443/bootstrap.sh | sudo PB_PIN='sha256//…' bash -s -- \
  --user barista -- <node> --only tailnet
```

It installs Tailscale from its apt repo, adds the UFW rules (and on cellar and
grinder, the forwarding and NAT), then prints a sign-in link: open it, sign in as
the admin, done. To skip the link, put a one-off, pre-authorized, tagged auth key
in `/etc/purrbrews/tailscale-authkey` (root, 0600) first; the step uses it once
and deletes it. Never put a key in `payload/payload.env`: it's served openly.

## Is it working?

Check from outside the house (phone hotspot), and tick the runbook only on what
you actually saw:

- `tailscale status` on americano lists the five nodes with `tag:purrbrews-node`,
  and your own devices.
- `ssh barista@<node>` works for all five, and `tailscale status` shows the
  connection as `direct` rather than `relay` (relay still works, just slower).
- A port that must stay closed is closed over the tailnet, e.g. from the laptop:
  `nc -zv -w3 percolator 443` (its tailnet address) and `nc -zv -w3 sieve 8080`
  both time out.
- Away from home: `https://immich.<domain>` and an admin page such as
  `https://pihole.<domain>` load after the Authelia login, and
  `nc -zv -w3 192.168.1.12 8123` (a direct port, Home Assistant on cellar) times out.
- Admin console → *Machines*: cellar and grinder show *Subnets* `192.168.0.0/23`,
  approved. On each, `systemctl is-active purrbrews-tailscale-nat` says `active`.
- On a node, `sudo ufw status | grep tailscale0` shows the SSH rule (plus the three
  forwarding rules on cellar and grinder), and
  `sudo nft list ruleset | grep -c 'ts-'` prints 0 (no Tailscale chains, in
  either iptables or nftables form).

## Day 2

- **Revoke a device:** admin console → *Machines* → the device → *Remove*. For a
  lost laptop, also take its SSH key out through purrbrews-bootstrap.
- **Run the step again** after changing `TAILSCALE_*` in `payload/payload.env`,
  or if a node was removed from the tailnet. It restates the whole configuration
  each time (`--reset`), and a node taken out of `TAILSCALE_SUBNET_ROUTERS` loses
  its NAT and forwarding (its three UFW route rules are removed by hand; it says
  so).

## Not done here (on purpose, for now)

- **The internet at large.** Apps for people without Tailscale go through
  Cloudflare Tunnel instead (`stacks/network/cloudflared/`), admin pages never.
- **Cloud VMs.** Join them with their own tag (say `tag:cloud`) and give that tag
  its own narrow grants in the policy; nothing about the nodes changes.
- **Headscale.** If the Tailscale-run control server ever bothers you, the
  clients can point at a self-hosted Headscale (`--login-server`); that needs a
  small public VPS, so it waits.
