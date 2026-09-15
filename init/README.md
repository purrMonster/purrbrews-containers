# init — fresh Debian → ready for container configs

One command on a freshly installed Debian 13 node takes it to the point where the
only thing left is the node's own stack (`stacks/<node>/…`). The scripts, the SSH
keys and the settings are served by **purrbrews-bootstrap on roastery**
(see [`../bootstrap/README.md`](../bootstrap/README.md)).

```
init/
├── purrbrews-init.sh              the node setup (run as root, via bootstrap.sh)
├── purrbrews-mac.sh               list / check / apply the fleet's cloned MACs
├── purrbrews-init.env.example     settings template → bootstrap/data/purrbrews-init.env
└── lib/
    ├── node-mac.sh                MAC derivation + validation
    ├── net-apply.sh               static IP + MAC switch with automatic rollback
    ├── sync-ssh-keys.sh           key sync from roastery (pinned), hourly timer
    └── purrbrews-pull.sh          daily fast-forward of /opt/purrbrews (anonymous, public repo)
```

## The fleet

| Node | IP | Cloned MAC (derived) |
|---|---|---|
| sieve | 192.168.0.10 | `02:33:68:72:0b:17` |
| percolator | 192.168.0.11 | `02:11:c2:56:e8:96` |
| cellar | 192.168.0.12 | `02:ba:2e:ea:5e:48` |
| mochaPot | 192.168.0.13 | `02:ff:72:b2:8f:c4` |
| grinder | 192.168.0.14 | `02:93:3c:b4:86:e8` |

Gateway `192.168.0.1`; `.1`–`.5` are reserved for routers and switches. Names are
matched case-insensitively (`MOCHAPOT` works), but the hostname is set exactly as written.

## Static IP + cloned MAC

The `network` step replaces the interface's DHCP profile with a NetworkManager profile
`purrbrews-<iface>` that holds the static IP **and** `ethernet.cloned-mac-address`.
Both are applied in a single link change.

- **Why clone the MAC:** the router, Pi-hole and every ARP table see the same device
  for `sieve`, even after a NIC swap, a new USB dongle or a reinstall.
- **Where the MAC comes from:** it's derived from the node name as
  `02:` + the first 5 bytes of `sha256("purrbrews:<name>")`. The `02` marks it as
  locally administered, so it can't clash with a real vendor MAC, and the same name
  always gives the same MAC. To keep a MAC the router already knows, set it in
  `NODE_MACS=cellar=aa:bb:…`.
- **Safety:** the switch runs detached (`systemd-run`), so a dropped SSH session can't
  interrupt it. It succeeds only if the new IP and MAC are on the link, the default
  route points at `GATEWAY`, and the gateway answers. Otherwise, within about 60 s,
  it restores the old MAC and profile. A second run while a switch is in progress
  is refused.
- **Re-running** with a changed IP or MAC builds `purrbrews-<iface>-next`, and swaps
  it in only after it has proven it works.
- **Wake-on-LAN** still targets the NIC's **burned-in** MAC. `purrbrews-mac.sh show`
  prints both.
- **Fleet-wide checks:** duplicate names, IPs or MACs, multicast MACs and `NODE_MACS`
  entries for unknown nodes are all refused before anything changes. Wi-Fi interfaces
  are refused too; the fleet is wired-only.

```bash
bash purrbrews-mac.sh list                    # table (runs in Git Bash on roastery too)
bash purrbrews-mac.sh list --format pihole    # paste into Pi-hole's static DHCP list
bash purrbrews-mac.sh list --format dnsmasq   # dhcp-host=MAC,IP,name
bash purrbrews-mac.sh show                    # on a node: expected vs current vs burned-in
sudo bash purrbrews-mac.sh apply              # on a node: (re)apply static IP + MAC now
```

Static leases in Pi-hole/router aren't required, since nodes don't use DHCP. They
reserve the addresses so nothing else is handed `.10–.14`, and give the nodes names
in Pi-hole's client list.

## Provisioning a node

1. Install Debian 13 (netinst, *SSH server* + *standard system utilities*). Using the
   node name as the hostname is optional.
2. On the node:
   ```bash
   wget -qO- --no-check-certificate https://<roastery-ip>:8443/bootstrap.sh | sudo bash -s -- sieve
   ```
   Confirm the TLS pin, set `barista`'s sudo password when asked, and answer the two
   safety prompts (SSH lock-down, IP/MAC switch). `--yes` skips the prompts and
   generates the sudo password into `/root/purrbrews-ops-password` instead.
3. Reconnect as `ssh barista@192.168.0.10` and continue in `/opt/purrbrews/stacks/sieve/`.

Re-running later needs no roastery for most steps:
`sudo bash /opt/purrbrews/init/purrbrews-init.sh`. Settings are kept in
`/etc/purrbrews/purrbrews-init.env` (root, 0600).

**Without roastery** (USB/scp route): put `purrbrews-init.env` and an `authorized_keys`
file next to `purrbrews-init.sh` and run `sudo bash purrbrews-init.sh sieve`.

## What it sets up

| Step | Result |
|---|---|
| `hostname` | hostname, plus a managed `/etc/hosts` block listing every node |
| `timezone` | `TZ` + NTP |
| `apt` | full upgrade, base tools, unattended security upgrades |
| `ops_user` | `barista`: in `sudo` (password-gated), **never** in `docker` |
| `ssh_keys` | keys from roastery (pinned TLS), kept in a managed block |
| `ssh_harden` | `sshd_config.d/00-purrbrews.conf`: key-only, no root, `AllowUsers barista` |
| `power` | lid close ignored; suspend/hibernate masked |
| `journald` | persistent journal capped at `JOURNAL_MAX_USE` |
| `docker` | Docker CE + Compose from Docker's repo; logs capped at 10 MB × 3 |
| `repo` | anonymous https clone of the public repo to `/opt/purrbrews` as barista (or fast-forward it) |
| `directories` | `/srv/data`, `/srv/media`, `/opt/purrbrews/.env` (NODE, NODE_IP, TZ, PUID/PGID, paths) |
| `timers` | `purrbrews-pull.timer` (daily), `purrbrews-ssh-keys.timer` (hourly) |
| `firewall` | UFW: deny incoming, SSH from `LAN_CIDR`; ufw-docker pinned by tag + SHA-256 |
| `network` | static IP + cloned MAC, detached, auto-rollback |

Options: `--only a,b`, `--skip a,b`, `--list-steps`, `--env FILE`, `--yes`.
Each run is logged to `/var/log/purrbrews/init-*.log`.

## Day-2 commands

```bash
systemctl list-timers 'purrbrews-*'
journalctl -u purrbrews-ssh-keys -n 20      # key syncs ("UNREACHABLE" = roastery asleep, harmless)
journalctl -u purrbrews-pull -n 20          # repo pulls
cat /var/log/purrbrews/net-apply.log        # IP/MAC switches and rollbacks
sudo /usr/local/lib/purrbrews/sync-ssh-keys.sh --dry-run
```

## Gotchas

- **Changing a node's MAC** makes the router and Pi-hole see a new device. Update any
  reservation that was keyed on the old MAC.
- **Public repo:** nodes need no credentials to pull, so nothing expires — but nothing
  secret may ever be committed. The script refuses a `GITHUB_TOKEN` or a URL with
  credentials. Set `PULL_HEALTHCHECK_URL` so a silently failing pull still alerts you.
- **`AllowUsers barista`** locks the installer account out of SSH (the console still
  works). Add it to `SSH_ALLOW_USERS` if you want to keep it.
- **`bad interpreter: /bin/bash^M`** means CRLF line endings. The repo forces LF; the
  env file tolerates either.
