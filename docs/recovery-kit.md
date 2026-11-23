# The recovery kit (flask)

**flask is the fleet's recovery kit: two encrypted, bootable USB sticks kept
unplugged, plus the Tier 1 keys on paper.** It's the one thing that isn't part of
the fleet, so it's what's left when the fleet, cellar and the Google account are
all gone. Scripts and READMEs say "copy X to flask" or "to the recovery kit"; this
page says what that means.

It was designed in the old fleet (runbook 2026-09-28, now
`deprecated/runbook.md`) and built with PowerShell on roastery
(`deprecated/stacks/roastery/flask`). Since the 2026-11 rebuild it is built from
americano, the Mac, with the scripts in [`recovery/`](../recovery). What goes on
it, and why, is unchanged.

Status: **scripts written (2026-11-18); the sticks are the owner's.** Stick A
already has Ventoy and booted twice in the old fleet (2026-09-30). Next:
[Building it](#building-it), once the new repository exists (phase 4 of the
[migration plan](migration-plan.md)): there's no point filling a vault with keys
that are about to change.

## What it must be

- **Offline.** It's never left plugged in, never on a network, never on a node.
  Anything online can be reached by whatever gets into the network, and one box
  with every key is the best target there is. Unplugged, nobody can reach it.
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
- The first day: a full write-and-read test of each (`f3write` and `f3read` on
  the Mac, `brew install f3`), before anything goes on it.

## Layout of each stick

[Ventoy](https://www.ventoy.net) on the stick, so it both boots and keeps a normal
**exFAT** partition that macOS, Windows, Debian, iOS and Android all read.

```
FLASK-A (exFAT)
├── debian-live-<ver>-amd64-xfce.iso   boots any x86 PC into a clean desktop
├── flask.kdbx                         the vault (KeePassXC)
├── tools/
│   ├── linux-amd64/   restic, rclone, KeePassXC AppImage
│   ├── windows-amd64/ restic.exe, rclone.exe, KeePassXC portable
│   └── darwin-arm64/, darwin-amd64/   restic, rclone, KeePassXC .dmg
├── RECOVERY.md                        what to do, written while calm
├── VERSIONS.txt                       what was built, when, from which versions
├── ventoy/
│   ├── ventoy.json                    tells Ventoy to inject the archive into the live ISO
│   └── flask_injection.tar.gz         the files it injects (below)
└── SHA256SUMS                         every file above except the vault
```

The live system runs with nothing installed and no network: restic and rclone are
single files, KeePassXC runs as an AppImage. Ventoy's persistence stays off, so
every boot starts clean. A Mac can't boot the stick (Apple Silicon can't boot x86
at all), so the Mac binaries and the KeePassXC disk image are there for using the
kit from a Mac instead.

**What the live system gets at boot** (Ventoy's
[LiveInjection](https://www.ventoy.net/en/doc_live_injection.html); the files are in
[`recovery/live/`](../recovery/live)): the Debian ISO itself is untouched, so its
signature still holds.

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
on (or turn Secure Boot off for the recovery). Phones open the vault only
(KeePassium or Strongbox on iOS, KeePassDX on Android), and only your own phone.

## What goes in the vault

[`recovery/vault.tiers`](../recovery/vault.tiers) is the list `fill-vault.sh`
copies; the tables below say why each one is there. Names only, never values:
the values are in each node's gitignored
`/opt/purrbrews/stacks/<group>/<app>/secrets.env.local`. A test checks the two
lists agree and that every name still exists in some app's `secrets.conf`.

**Tier 1: without these, nothing restores.** Also on the paper.

| Secret | Where |
|---|---|
| `RESTIC_PASSWORD` | every node's restic (the same everywhere) |
| `RCLONE_CRYPT_PASSWORD`, `RCLONE_CRYPT_SALT` | cellar/restic |

Every other secret below is also inside the restic backups, so with Tier 1 and
either the repository or the Drive copy you can get the rest back. The vault holds
them so a partial failure doesn't need a full restore first.

**Tier 2: keys that match the data.** Restore these with their matching data;
with a new one instead, the data stays unreadable.

| Secret | Where | Lose it and |
|---|---|---|
| `N8N_ENCRYPTION_KEY` | grinder/n8n | every stored credential in n8n is unreadable |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | percolator/authelia | every 2FA device has to be enrolled again |
| `LLDAP_KEY_SEED`, `LLDAP_JWT_SECRET` | percolator/lldap | the seed makes LLDAP's server key: every user's password stops working |
| `PAPERLESS_SECRET_KEY` | percolator/paperless | sessions and signed links |
| `FRESHRSS_OIDC_CRYPTO_KEY` | percolator/freshrss | FreshRSS's OIDC sign-in |
| `SPEEDTEST_TRACKER_APP_KEY` | grinder/speedtest-tracker | its encrypted settings |
| `KOMODO_DATABASE_PASSWORD`, `KOMODO_JWT_SECRET` | cellar/komodo | Komodo's database and sessions |
| `OPENCLOUD_JWT_SECRET`, `OPENCLOUD_TRANSFER_SECRET`, `OPENCLOUD_MACHINE_AUTH_API_KEY`, `OPENCLOUD_SYSTEM_USER_API_KEY`, `OPENCLOUD_URL_SIGNING_SECRET` | grinder/opencloud | restore with its generated config and data |
| `CAFE_APP_ENCRYPTION_KEY` | percolator/purrcafe | saved mailboxes can't be read |
| `CAFE_ACTUAL_ENCRYPTION_PASSWORD` | percolator/purrcafe | the budget file's end-to-end encryption password, if it has one: lose it and the budget can't be opened |

OpenCloud also requires the matching whole `opencloud/config` and `opencloud/data`
restic restore. Its generated `opencloud.yaml` holds internal IDM passwords,
service-account credentials and IDs that are not in env files. Keep it as a
protected vault attachment; `fill-vault.sh` only copies named env secrets and
cannot replace that attachment or the full backup. (`OPENCLOUD_THUMBNAILS_TRANSFER_TOKEN`
was in the old list; OpenCloud 9.1 dropped it.)

**Tier 3: emergency logins and directory binds.**

| Secret | Where |
|---|---|
| `LLDAP_ADMIN_PASSWORD` | percolator/lldap |
| `PAPERLESS_ADMIN_PASSWORD` | percolator/paperless |
| `RADICALE_LDAP_READER_PASSWORD` | percolator/radicale; reader bind only, not a human login |
| `VAULTWARDEN_ADMIN_PASSWORD` | percolator/vaultwarden |
| `KOMODO_INIT_ADMIN_PASSWORD` | cellar/komodo |
| `PIHOLE_WEBPASSWORD` | mochaPot/pihole-secondary (the primary on sieve signs in through Authelia) |
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
| `MAIL_RELAY_PASSWORD` | percolator/mail-relay (a Purelymail app password) |
| `LLM_UPSTREAM_API_KEY` | grinder/litellm (once a provider is chosen) |

**Outside the repo**, by hand in KeePassXC:

- barista's sudo password on each node;
- sign-in and **2FA recovery codes** for the accounts the fleet depends on: the
  Google account that holds the Drive copy, Cloudflare, GitHub, Purelymail, the
  LLM provider, and the identity provider behind Tailscale. Losing the phone must
  not lock you out of these.

**Not needed:** database passwords, OIDC client secrets and session secrets. They
can be generated again, and they're in the backups.

## Building it

**Ventoy**, once per stick, from Linux: macOS has no Ventoy installer. Stick A
already has it. For B (or a replacement), any Linux will do: a node, or stick A
booted on a ThinkCentre (it has a terminal).

```bash
# from github.com/ventoy/Ventoy/releases: ventoy-<ver>-linux.tar.gz and sha256.txt
grep linux.tar.gz sha256.txt | sha256sum -c -
tar xzf ventoy-*-linux.tar.gz && cd ventoy-*/
lsblk -o NAME,SIZE,TRAN,MODEL                       # the stick: TRAN usb, ~57G. Check twice.
sudo sh Ventoy2Disk.sh -i -s -L FLASK-B /dev/sdX    # -s Secure Boot support, -L the label
```

`-i` refuses a disk that already has Ventoy; it wipes the whole stick. Write A or
B on the stick itself.

**Then the kit**, on americano with both sticks plugged in (`brew install gnupg`
once):

```bash
cd recovery
./make-flask.sh --prepare   # download and verify only; good to run first
./make-flask.sh             # write every FLASK-A/B stick
./make-flask.sh --check     # later: check each against its SHA256SUMS, compare the vaults
```

It downloads the Debian Live ISO, restic, rclone and KeePassXC at the versions
pinned in the script, checks each against its project's signed checksums (keys
pinned by fingerprint), and stops before touching a stick if anything doesn't
verify. It writes only to USB disks with Ventoy and a FLASK-A/B exFAT partition,
replaces `tools/`, reads everything back against `SHA256SUMS`, and never touches
`flask.kdbx`. Its downloads are kept in `~/Library/Caches/purrbrews-flask`.

**Then the vault.** Make `flask.kdbx` on stick A in KeePassXC (the app on
americano, or the `.dmg` from `tools/darwin-*`; *Database > New Database*: that's
where the master password is chosen), and fill it with
[`fill-vault.sh`](../recovery/fill-vault.sh):

```bash
./fill-vault.sh --dry-run    # which entries, from where; no vault, no values shown
./fill-vault.sh              # asks for the master password, writes Tiers 1-4
```

It reads each secret over SSH (as barista, with americano's key) into memory and
hands it to `keepassxc-cli` on standard input, so no value reaches the screen, a
file, the clipboard or a chat. Run it again after a secret changes: existing
entries get the new value. The rest by hand in KeePassXC ("Outside the repo"
above, `rclone.conf` once Drive exists, and `opencloud.yaml`), then copy
`flask.kdbx` to B and `./make-flask.sh --check`.

**Then the paper:** Tier 1 (text and a QR code each), the master password, and the
hand mount above. Sealed, kept apart from both sticks.

## Testing it

Boot each stick on a ThinkCentre **with the network cable out**: that's both the
offline test and the firmware test (the boot menu key, F12, and Secure Boot's key
enrolment). Check three things: the kit opens by itself, **flask: KeePassXC**
opens the vault, and `restic version` runs. A ThinkCentre that's already a node
boots back into Debian afterwards unchanged; the live system writes nothing to its
disk.

A Mac can't stand in for that: Apple Silicon can't boot x86, and an emulator
doesn't test the firmware. Fixes can be tried in the running live system first
(`sudo nano /usr/local/bin/flask-keepassxc`), then go into `recovery/live/` and
one rebuild.

## Using it

[`recovery/RECOVERY.md`](../recovery/RECOVERY.md), on each stick and in the repo:
using the tools on a Mac, Windows or the booted stick, then three cases:

- **A.** One node is gone, cellar is fine: rebuild it, settings, files, then
  databases from the dumps.
- **B.** cellar is gone: a new cellar, the repository back from
  `drive-crypt:repo`, then A.
- **C.** Nothing online: read the offline HDD directly, or copy it to a new
  cellar, then A.

## Upkeep

- **Every year, and whenever a secret in the tables changes:** plug both sticks
  into americano, `./make-flask.sh --check`, `./fill-vault.sh` into A, copy A's
  vault to B. Once a year also bump the versions at the top of `make-flask.sh`
  and run it: the current Debian Live ISO and tools. `--check` again, eject,
  unplug, and one boot of the new build on a ThinkCentre.
- **When a Tier 1 key changes:** new paper too, and destroy the old envelope.
- The runbook's Backlog carries the next yearly date.
