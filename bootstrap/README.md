# bootstrap — serve node setup from roastery

A small container on roastery's Docker Desktop. Fresh nodes fetch the init scripts,
the SSH public keys and the fleet settings from it. Nothing is copied to USB sticks,
nothing depends on GitHub for keys, and **nothing it serves is secret** — so there is
no password. (The repo itself is cloned anonymously from the public GitHub mirror.)

```
roastery (Docker Desktop)                         fresh Debian node
┌───────────────────────────────┐   HTTPS :8443   ┌──────────────────────────────┐
│ purrbrews-bootstrap (nginx)   │ ◄────────────── │ wget … /bootstrap.sh | bash  │
│  /bootstrap.sh                │  pinned TLS key │  1. pin roastery's TLS key   │
│  /files/*  + SHA256SUMS       │                 │  2. scripts, checksummed     │
│  /keys/authorized_keys  ◄─ data/authorized_keys │  3. fleet settings           │
│  /config/purrbrews-init.env ◄─ data/…init.env   │  4. purrbrews-init.sh        │
└───────────────────────────────┘                 │  hourly: re-sync keys ───────┤
                                                  └──────────────────────────────┘
```

| Path | Access | Source |
|---|---|---|
| `/bootstrap.sh` | open | baked into the image |
| `/files/…` + `SHA256SUMS` | open | `init/` baked in at build |
| `/keys/authorized_keys` | open (public keys) | `data/authorized_keys`, live |
| `/config/purrbrews-init.env` | open (no secrets — the container refuses to start if it finds `OPS_PASSWORD_HASH` or `GITHUB_TOKEN`) | `data/purrbrews-init.env`, live |

## One-time setup on roastery

1. **Give roastery a fixed address.** Add a DHCP reservation on the router for its USB
   Ethernet adapter. Every node stores the bootstrap URL, and the
   hourly key sync stops working if roastery's IP changes.
2. **Data files** (gitignored; they never go into the image):
   ```powershell
   cd <path-to-repo>\bootstrap
   mkdir data
   Copy-Item ..\init\purrbrews-init.env.example data\purrbrews-init.env   # works as-is for the fleet
   Copy-Item $HOME\.ssh\id_ed25519.pub data\authorized_keys              # add more keys, one per line
   ```
   To use a different port, create `bootstrap\.env` with `BOOTSTRAP_PORT=…`.
3. **Start it:**
   ```powershell
   docker compose up -d --build
   docker compose logs bootstrap      # note the "TLS pin" line
   ```
4. **Allow the port on the LAN** (admin PowerShell; the network profile must be *Private*):
   ```powershell
   New-NetFirewallRule -DisplayName "purrbrews-bootstrap" -Direction Inbound -Protocol TCP `
     -LocalPort 8443 -RemoteAddress 192.168.0.0/24 -Profile Private -Action Allow
   ```

The TLS key lives in the `certs` volume, so the pin stays the same across rebuilds.
Don't run `docker compose down -v` unless you mean to re-pin every node.

## Provisioning a node

On the fresh Debian install, as the installer user (Debian's netinst has `wget`,
and may not have `curl`):

```bash
wget -qO- --no-check-certificate https://<roastery-ip>:8443/bootstrap.sh | sudo bash -s -- sieve
```

It prints roastery's TLS pin and asks you to confirm it matches the logs, then
`purrbrews-init.sh` takes over. The only thing you type is `barista`'s sudo password. To skip the pin
prompt, pass the pin up front:

```bash
wget -qO- --no-check-certificate https://<roastery-ip>:8443/bootstrap.sh \
  | sudo PB_PIN='sha256//…' bash -s -- sieve
```

Options after the node name go to `purrbrews-init.sh` (`--yes`, `--skip network`, …).

## Day to day

- **Add or revoke an SSH key:** edit `data/authorized_keys`. Nodes pick it up within the
  hour, or run `sudo systemctl start purrbrews-ssh-keys` on a node.
- **Changed something in `init/`:** run `docker compose up -d --build`.
  Already-provisioned nodes get `init/` through their daily repo pull instead.
- **Changed the settings file:** it's served live. It only matters for nodes provisioned
  from now on; existing nodes keep `/etc/purrbrews/purrbrews-init.env`.
- **Roastery asleep:** the key sync exits `75` ("unreachable, nothing changed"), which
  is not a failure. Keys stay as they were until roastery is back, so a revocation
  waits for roastery to wake up.
- **A different TLS key answers** (container recreated with a new volume, or someone
  impersonating roastery): the key sync fails loudly (`systemctl --failed`) and changes
  nothing. To re-pin after a deliberate reset, update `SSH_KEYS_PINNED_PUBKEY` in
  `/etc/purrbrews/purrbrews-init.env` and run
  `sudo bash /opt/purrbrews/init/purrbrews-init.sh --only ssh_keys`.

## Security notes

- The first contact is trust-on-first-use unless you pass `PB_PIN`. Everything after
  that, including every hourly key sync, is pinned to that key.
- Scripts are checked against `SHA256SUMS` from the same pinned server. That protects
  against corruption, not against a compromised roastery.
- Nothing served is secret: scripts (also public on GitHub), public SSH keys and fleet
  settings (node names, IPs, schedules). The container refuses to start if the settings
  file contains `OPS_PASSWORD_HASH` or `GITHUB_TOKEN`, and `bootstrap.sh` checks again.
- What *is* worth protecting is integrity: whoever controls roastery controls which SSH
  keys the fleet trusts. Keep roastery's own login strong.
- Behind Docker Desktop's NAT, nginx may see every client as a Docker address. The
  Windows Firewall rule above is what actually limits access to the LAN.
- The container runs read-only, with all capabilities dropped except those nginx needs,
  and `no-new-privileges`.
