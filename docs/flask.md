# flask

**flask is the fleet's recovery kit: two encrypted, bootable USB sticks kept
unplugged, plus the Tier 1 keys on paper.** It's the one thing that isn't part of
the fleet, so it's what's left when the fleet, roastery and the Google account
are all gone. Scripts and READMEs say "copy X to flask"; this page says what that
means. Decided 2026-09-28 (runbook).

Status: **planned, the sticks are on order.** Nothing on this page exists yet
except the plan.

## What it must be

- **Offline.** It's never left plugged in, never on a network, never on a Pi or a
  node. Anything online can be reached by whatever gets into the network, and one
  box with every key is the best target there is. Unplugged, nobody can reach it.
- **Outside the fleet.** Not Vaultwarden on percolator: its data is inside the
  restic repository, so you'd need the password to get the password.
- **More than one copy, in more than one place.** Flash left in a drawer fades
  and fails without warning. Two sticks from different brands, kept apart, plus
  paper.
- **Encrypted, with the master password in your head.** A stick found in a drawer
  must be useless. The only other copy of the master password is the sealed
  paper.

## The three copies

| Copy | Where | Holds |
|---|---|---|
| **Stick A** | at home, away from the rack | everything below |
| **Stick B** | a different place (another flat, a relative's) | the same, checked identical |
| **Paper** | a sealed envelope, not with either stick | the Tier 1 keys (text and QR) and the vault's master password |

## Hardware

- Two **64 GB USB 3.x** sticks, **dual connector (USB-A + USB-C)**, metal body,
  **different brands** (Samsung, SanDisk or Kingston), bought from the brand's
  store or Amazon itself. Fake-capacity sticks are common on marketplaces.
- The first day: **H2testw** on each (fills the whole stick and reads it back),
  before anything goes on it.

## Layout of each stick

[Ventoy](https://www.ventoy.net) on the stick, so it both boots and keeps a normal
**exFAT** partition that Windows, Debian, macOS, iOS and Android all read.

```
FLASK (exFAT)
├── debian-live-<ver>-amd64-xfce.iso   boots any x86 PC into a clean desktop
├── flask.kdbx                         the vault (KeePassXC)
├── tools/
│   ├── linux-amd64/   restic, rclone, KeePassXC AppImage
│   ├── windows-amd64/ restic.exe, rclone.exe, KeePassXC portable
│   └── darwin-arm64/, darwin-amd64/   restic, rclone
├── RECOVERY.md                        what to do, written while calm
└── SHA256SUMS                         every file above except the vault
```

The live system runs with nothing installed and no network: restic and rclone are
single files, KeePassXC runs as an AppImage. Ventoy's persistence stays off, so
every boot starts clean.

**Booting it:** Ventoy asks once per machine to enrol its key when Secure Boot is
on (or turn Secure Boot off for the recovery). Apple Silicon Macs can't boot it:
use the Mac binaries and the vault from the stick instead. Phones open the vault
only (KeePassium or Strongbox on iOS, KeePassDX on Android), and only your own
phone.

## What goes in the vault

Names only here; the values are in each node's gitignored
`stacks/<node>/<app>/secrets.env.local`. Read them yourself in your own terminal,
never through a chat:

```bash
ssh barista@192.168.0.12 "grep -E '^(RESTIC_PASSWORD|RCLONE_CRYPT_PASSWORD|RCLONE_CRYPT_SALT)=' \
  /opt/purrbrews/stacks/cellar/restic/secrets.env.local"
```

**Tier 1: without these, nothing restores.** Also on the paper.

| Secret | Where |
|---|---|
| `RESTIC_PASSWORD` | cellar/restic (the same on every node) |
| `RCLONE_CRYPT_PASSWORD`, `RCLONE_CRYPT_SALT` | cellar/restic |

Every other secret below is also inside the restic backups, so with Tier 1 and
either the repository or the Drive copy you can get the rest back. The vault holds
them so a partial failure doesn't need a full restore first.

**Tier 2: keys that encrypt app data.** Restore the data with a different key and
that data is gone.

| Secret | Where | Lose it and |
|---|---|---|
| `N8N_ENCRYPTION_KEY` | grinder/n8n | every stored credential in n8n is unreadable |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | percolator/authelia | every 2FA device has to be enrolled again |
| `LLDAP_KEY_SEED`, `LLDAP_JWT_SECRET` | percolator/lldap | the seed makes LLDAP's server key: every user's password stops working |
| `PAPERLESS_SECRET_KEY` | percolator/paperless | sessions and signed links |
| `FRESHRSS_OIDC_CRYPTO_KEY` | percolator/freshrss | FreshRSS's OIDC sign-in |
| `SPEEDTEST_TRACKER_APP_KEY` | grinder/speedtest-tracker | its encrypted settings |
| `KOMODO_DATABASE_PASSWORD`, `KOMODO_JWT_SECRET` | cellar/komodo | Komodo's database and sessions |

**Tier 3: emergency logins, for when Authelia or LLDAP is down.**

| Secret | Where |
|---|---|
| `LLDAP_ADMIN_PASSWORD` | percolator/lldap |
| `PAPERLESS_ADMIN_PASSWORD` | percolator/paperless |
| `NEXTCLOUD_ADMIN_PASSWORD` | percolator/nextcloud |
| `VAULTWARDEN_ADMIN_PASSWORD` | percolator/vaultwarden |
| `KOMODO_INIT_ADMIN_PASSWORD` | cellar/komodo |
| `PIHOLE_WEBPASSWORD` | mochaPot/pihole |
| `NTFY_ADMIN_PASSWORD` | sieve/ntfy |
| `ESPHOME_DASHBOARD_PASSWORD` | grinder/esphome |
| `SPEEDTEST_TRACKER_ADMIN_PASSWORD` | grinder/speedtest-tracker |
| `SMB_BARISTA_PASSWORD` | cellar/smb |

**Tier 4: outside accounts.** Re-creatable, but slowly.

| Secret | Where |
|---|---|
| `CF_DNS_API_TOKEN` | every node's traefik |
| `TUNNEL_TOKEN` | sieve/cloudflared |
| `RCLONE_DRIVE_CLIENT_ID`, `RCLONE_DRIVE_CLIENT_SECRET` | cellar/restic (once Drive is set up) |
| `/etc/purrbrews/rclone.conf` (attach the file) | cellar, root's (once Drive is set up) |
| `HEALTHCHECKS_PING_URL` | sieve/gatus |
| `NTFY_URL` | every node's restic |

**Outside the repo:**

- barista's sudo password on each node;
- roastery's Windows administrator password;
- sign-in and **2FA recovery codes** for the accounts the fleet depends on: the
  Google account that holds the Drive copy, Cloudflare, GitHub, and the identity
  provider behind Tailscale. Losing the phone must not lock you out of these.

**Not needed:** database passwords, OIDC client secrets and session secrets. They
can be generated again, and they're in the backups.

## Building it

`make-flask.ps1` on roastery (to be written):

1. Downloads the Debian Live ISO and checks it against Debian's signed
   `SHA512SUMS`; downloads restic, rclone and KeePassXC for each platform and checks
   their published checksums. Anything that doesn't verify stops the run.
2. Lays out `tools/`, `RECOVERY.md` and the ISO on the stick, writes `SHA256SUMS`.
3. With two sticks in, compares them file by file.

By hand, once per stick: install Ventoy (its own tool, one click), and fill
`flask.kdbx` in KeePassXC from the tables above. The vault's contents never pass
through a script, the repo or a chat.

## Using it

`RECOVERY.md` (to be written) covers three cases, each ending in `restic check`
and the restore test:

1. **A node or roastery is gone, the repository is fine:** rebuild the node, then
   `backup.sh restic restore`.
2. **roastery is gone:** restore from `drive-crypt:repo` with rclone, using
   `rclone.conf` from the vault.
3. **No roastery, no Drive, no network:** boot the stick, plug in the offline HDD,
   restore from it directly.

## Upkeep

- **Every year, and whenever a secret in the tables changes:** plug both sticks
  into roastery, `sha256sum -c SHA256SUMS`, open the vault, update it, copy A to B,
  compare. Swap in the current Debian Live ISO and tools. Unplug.
- **When a Tier 1 key changes:** new paper too, and destroy the old envelope.
- The runbook's backlog carries the next yearly date.
