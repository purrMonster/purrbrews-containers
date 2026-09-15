# PurrBrews Runbook

Dated design decisions for this repo, newest first. Each entry records *why*, so
changes can be made later without re-deriving the reasoning.

## Backlog / open items

- [ ] Publish the repo on GitHub (public) and enable Secret scanning + Push protection
- [ ] Workstation: DHCP reservation, `bootstrap/data/` (settings + `authorized_keys`), `docker compose up -d --build`, firewall rule for 8443
- [ ] First real node through `bootstrap.sh`, at the console (the network step has not yet run on real hardware)
- [ ] Add stacks node by node, each with its own `stacks/<node>/README.md`
- [ ] Optional: paste `purrbrews-mac.sh list --format pihole` into Pi-hole's static DHCP list

---

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
