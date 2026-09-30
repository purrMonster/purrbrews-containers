# flask

**flask is the fleet's recovery kit: two encrypted, bootable USB sticks kept
unplugged, plus the Tier 1 keys on paper.** It's the one thing that isn't part of
the fleet, so it's what's left when the fleet, roastery and the Google account
are all gone. Scripts and READMEs say "copy X to flask"; this page says what that
means. Decided 2026-09-28 (runbook).

Status: **sticks here (2026-09-28); script and recovery guide written.** Next: test
the sticks, Ventoy, `make-flask.ps1`, the vault, the paper (runbook, 2026-09-28).

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
| **Paper** | a sealed envelope, not with either stick | the Tier 1 keys (text and QR), the vault's master password, and the five-line hand mount (below) |

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
├── VERSIONS.txt                       what was built, when, from which versions
├── ventoy/
│   ├── ventoy.json                    tells Ventoy to inject the archive into the live ISO
│   └── flask_injection.tar.gz         the files it injects (below)
└── SHA256SUMS                         every file above except the vault
```

The live system runs with nothing installed and no network: restic and rclone are
single files, KeePassXC runs as an AppImage. Ventoy's persistence stays off, so
every boot starts clean.

**What the live system gets at boot** (Ventoy's
[LiveInjection](https://www.ventoy.net/en/doc_live_injection.html); the files are in
[`stacks/roastery/flask/live/`](../stacks/roastery/flask/live)): the Debian ISO itself
is untouched, so its signature still holds.

- `mount-flask`, run at login: mounts the kit **read-only at `/mnt/flask`** and opens it.
  Plain `mount /dev/sdX1` fails there ("busy"), because the live system runs from that
  partition; Ventoy (1.1.01+) exposes it again as `/dev/mapper/sdX1`, which mounts.
- **flask: KeePassXC (vault)** in the menu: runs the AppImage with
  `--appimage-extract-and-run`. The live system has no libfuse2, and offline it can't
  be installed; unpacked into `/tmp`, the AppImage doesn't need it.
- `restic` and `rclone` on the PATH, running from the stick.

**On the paper, with the Tier 1 keys**, the hand mount, in case the injection ever
doesn't run (the instructions on the stick are on the partition you can't open yet):

```
lsblk -o NAME,SIZE,FSTYPE,LABEL        # find FLASK-A, e.g. sdb1
sudo udevadm trigger; ls /dev/mapper/
sudo mkdir -p /mnt/flask
sudo mount -o ro,uid=1000,gid=1000 /dev/mapper/sdb1 /mnt/flask
KeePassXC: cp the AppImage to /tmp, run it with --appimage-extract-and-run
```

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
| `CF_DNS_API_TOKEN` | every node's traefik, a different token on each (one entry per node) |
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

By hand, once per stick, in this order:

1. **H2testw** on the empty stick (from heise.de): *Write + Verify*, all space.
   Anything but "Test finished without errors" at about the stick's size, and it
   goes back.
2. **Ventoy** (github.com/ventoy/Ventoy/releases, `windows.zip`; check its SHA-256
   against the release's `sha256.txt`): `Ventoy2Disk.exe` → the stick → *Option →
   Secure Boot Support* on, partition style MBR → Install. Then rename the big
   partition **FLASK-A** or **FLASK-B**, and write A or B on the stick itself.

Then [`stacks/roastery/flask/make-flask.ps1`](../stacks/roastery/flask/make-flask.ps1)
on roastery, with the sticks plugged in:

```powershell
cd stacks\roastery\flask
.\make-flask.ps1                # download, verify, write every FLASK-A/B stick
.\make-flask.ps1 -Check         # later: check each against its SHA256SUMS, compare the vaults
```

It downloads the Debian Live ISO, restic, rclone and KeePassXC at the versions
pinned in the script, checks each against its project's signed checksums (keys
pinned by fingerprint), and stops before touching a stick if anything doesn't
verify. It writes only to USB disks with Ventoy and a FLASK-A/B exFAT partition,
mirrors `tools/`, reads everything back against `SHA256SUMS`, and never touches
`flask.kdbx`.

Then the vault. Make `flask.kdbx` on stick A in KeePassXC
(`tools\windows-amd64\KeePassXC\KeePassXC.exe`, *Database > New Database*; that's where
the master password is chosen), and fill it with
[`fill-vault.ps1`](../stacks/roastery/flask/fill-vault.ps1):

```powershell
.\fill-vault.ps1 -DryRun         # which entries, from where; no vault, no values shown
.\fill-vault.ps1                 # asks for the master password, writes Tiers 1-4
```

It reads each secret over SSH into memory and hands it to `keepassxc-cli` on
standard input, so no value reaches the screen, a file, the clipboard or a chat.
Run again after a secret changes: existing entries get the new value. The rest by
hand in KeePassXC ("Outside the repo" above, and `rclone.conf` once Drive exists),
then copy `flask.kdbx` to B and `.\make-flask.ps1 -Check`.

## Testing it

Boot the stick in a VirtualBox VM on roastery: no reboot, and a VM with no network
adapter is exactly the offline test. VirtualBox can't boot a passed-through USB
device, so the VM gets the whole stick as a raw disk. Elevated PowerShell:

```powershell
Get-Disk | Where-Object BusType -eq USB | Format-Table Number, FriendlyName, Size
Get-Partition -DiskNumber 1 | Get-Volume        # FLASK-A or FLASK-B, and VTOYEFI? (1 = the number above)
Set-Disk -Number 1 -IsOffline $true             # Windows lets go of it
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\purrbrews\flask\vm" | Out-Null
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" createmedium disk `
  --filename "$env:LOCALAPPDATA\purrbrews\flask\vm\flask-a.vmdk" `
  --format VMDK --variant RawDisk --property RawDrive=\\.\PhysicalDrive1
```

VirtualBox itself run as administrator: a Debian 64-bit VM, EFI on, 4 GB, no disk
in the wizard, then `flask-a.vmdk` on the SATA controller and the network adapter
off. Boot, check the three things (the kit opens itself, **flask: KeePassXC** opens
the vault, `restic version` runs), power off, `Set-Disk -Number 1 -IsOffline $false`.

- The disk number changes with the port and other drives. Check it every time; if
  it moved, delete the `.vmdk` and make it again. A stale one could point at
  roastery's own disk.
- Fixes can be tried inside the running live system first (`sudo nano
  /usr/local/bin/flask-keepassxc`), then go into `stacks/roastery/flask/live/` and one
  rebuild.
- A VM doesn't test the firmware: the boot menu key and Secure Boot's key
  enrolment. The last test of a rebuild is one boot on a real PC, not roastery.

## Using it

[`RECOVERY.md`](../stacks/roastery/flask/RECOVERY.md), on each stick and in the repo:
booting the stick and using the tools, then three cases:

- **A.** One node is gone, roastery is fine: rebuild it, settings, files, then
  databases from the dumps.
- **B.** roastery is gone: the repository back from `drive-crypt:repo`, onto a new
  roastery, then A.
- **C.** Nothing online: read the offline HDD directly, or copy it to a new
  roastery, then A.

## Upkeep

- **Every year, and whenever a secret in the tables changes:** plug both sticks
  into roastery, `.\make-flask.ps1 -Check`, open the vault, update it, copy A to B.
  Once a year also bump the versions at the top of `make-flask.ps1` and run it:
  the current Debian Live ISO and tools. `-Check` again, unplug.
- **When a Tier 1 key changes:** new paper too, and destroy the old envelope.
- The runbook's backlog carries the next yearly date.
