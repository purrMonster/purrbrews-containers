# RECOVERY

You're reading this because something is gone. Take it slowly: nothing below
deletes anything, and every restore goes into a scratch folder first unless it
says otherwise. This file lives on each flask stick and in the repo at
`recovery/RECOVERY.md`; the repo's copy is the current one, if GitHub is still
there for you.

**Where the backups are** (newest first):

| Copy | Where | Needs |
|---|---|---|
| The repository | cellar (192.168.1.12), `/srv/backup/restic`; the nodes reach it as `sftp:burmilla@192.168.1.12:/restic` | `RESTIC_PASSWORD` |
| Google Drive | `drive-crypt:repo` (the folder `purrbrews-restic`, names encrypted) | the Google account, `RCLONE_CRYPT_PASSWORD`, `RCLONE_CRYPT_SALT`, `RESTIC_PASSWORD` |
| Offline HDD | one of the two old HDDs, folder `restic/`, as old as its last turn in the dock | `RESTIC_PASSWORD` |
| Database dumps | cellar, `/srv/dumps/<node>/` | nothing; they're plain files (and inside all three above) |

Every secret is in `flask.kdbx` on this stick. Tier 1 (the three above) is also
on the paper.

**Pick your case:**

- One node is gone, cellar is fine → **A**
- cellar (or its NVMe) is gone → **B**, then **A** for each node
- No cellar, no Drive, no internet → **C**, then **A**

The nodes, for reference: sieve .10 (network), percolator .11 (apps), cellar .12
(backups, fleet management), mochaPot .13 (home), grinder .14 (automation, AI),
all on 192.168.1.0/24. Each node's checkout is `/opt/purrbrews`; its commands
are in `/opt/purrbrews/nodes/<node>/`, and every command below that starts with
`./` is run from there.

---

## Before any case: tools and the vault

**On a Mac** (americano or any you trust): `tools/darwin-arm64/` (Apple Silicon)
or `tools/darwin-amd64/` (Intel) has `restic`, `rclone` and the KeePassXC `.dmg`.
Copy restic and rclone to a folder of yours first and run
`xattr -d com.apple.quarantine restic rclone` if macOS refuses them. A Mac can't
boot the stick.

**On Windows** (any PC you trust): `tools\windows-amd64\` has `restic.exe`,
`rclone.exe` and `KeePassXC\KeePassXC.exe`. Run them from the stick.

**On a PC you don't trust, or with nothing working: boot this stick.**

1. Plug it in, power on, open the boot menu (F12 on the ThinkCentres; F11, F8
   or Esc elsewhere) and pick the USB stick.
2. First time on a PC with Secure Boot: Ventoy shows a blue *Verification
   failed* screen. Choose **Enroll key from disk** → `VTOYEFI` →
   `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` → Continue → Yes → Reboot, and boot the
   stick again. (Or turn Secure Boot off in the firmware for now.)
3. In Ventoy's menu pick `debian-live-…-xfce.iso` → *Boot in normal mode* →
   *Live system*. It needs no password; if something asks, the user is `user`,
   the password `live`.
4. **The kit mounts itself** at `/mnt/flask`, read-only, and a file manager opens
   on it (Ventoy injects a small script at boot; `make-flask.sh` puts it there).
   In the applications menu: **flask: KeePassXC (vault)** opens `flask.kdbx`, and
   **flask: open the kit** reopens the folder. In a terminal, `restic` and
   `rclone` just work: they run from the stick.

**If `/mnt/flask` is empty** (the injection didn't run), mount it by hand. This is
also on the paper, because this file is on the partition you can't open yet:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL          # FLASK-A: e.g. sdb1, exfat, ~57G
ls /dev/mapper/                          # Ventoy's copy of it, e.g. sdb1
sudo udevadm trigger                     # only if it's missing, then ls again
sudo mkdir -p /mnt/flask
sudo mount -o ro,uid=1000,gid=1000 /dev/mapper/sdb1 /mnt/flask
```

Mounting `/dev/sdb1` itself fails ("busy"): the live system is running from that
partition. The `/dev/mapper/` copy is how Ventoy lets you read it.

**KeePassXC without the menu:** it's an AppImage, and the live system has no
libfuse2 (offline, it can't be installed), so run it unpacked instead:

```bash
cp /mnt/flask/tools/linux-amd64/KeePassXC-*.AppImage /tmp/kp && chmod +x /tmp/kp
cd /tmp && ./kp --appimage-extract-and-run /mnt/flask/flask.kdbx &
```

Nothing you do in the live system is kept after a reboot. That's the point;
save what you restore to a real disk.

**Give restic its password without it landing in the shell history:**

```bash
read -rs RESTIC_PASSWORD && export RESTIC_PASSWORD      # paste, Enter
```

On Windows: `$env:RESTIC_PASSWORD = Read-Host -MaskInput` (PowerShell 7), or
paste it into `$env:RESTIC_PASSWORD = '...'` and close the window after.

---

## A. One node is gone; cellar still has the repository

This is the normal case, and you don't need to boot the stick for it.

1. **Rebuild the node** with the bootstrap: `payload/README.md` in the repo (the
   one-liner from americano, with the node's name). It installs the OS settings,
   Docker, the checkout and the node's identity. Then `./setup-secrets.sh`.
   Don't start its apps yet.
2. **Let it reach cellar again.** A new install has a new backup key:
   `sudo ./backup.sh install` prints its line (also in
   `/etc/purrbrews/backup-authorize.txt`). On cellar, replace that node's line in
   `/opt/purrbrews/stacks/backup/restic/backup.keys` and run
   `sudo /opt/purrbrews/stacks/backup/restic/repo-setup.sh` and
   `sudo /opt/purrbrews/stacks/backup/restic/dump-store-setup.sh`.
   If the node *was* cellar, it's **B**, not this.
3. **See what there is:** `sudo ./backup.sh restic snapshots --host <node>`.
4. **Settings first**, into a scratch folder, then copied into place:

```bash
sudo ./backup.sh restic restore latest --host <node> --tag files \
  --target /var/tmp/restore --include /opt/purrbrews --include /etc/purrbrews
sudo find /var/tmp/restore/opt/purrbrews -name '*.env.local' -o -name .env   # check before copying
sudo cp -a /var/tmp/restore/opt/purrbrews/.env /opt/purrbrews/.env
sudo cp -a /var/tmp/restore/opt/purrbrews/nodes/<node>/.env.local /opt/purrbrews/nodes/<node>/
cd /var/tmp/restore/opt/purrbrews && for f in stacks/*/*/secrets.env.local; do
  sudo cp -a "$f" "/opt/purrbrews/$f"; done; cd -
```

   These carry the Tier 2 keys that match the data, so the data restored next
   can be read. `/etc/purrbrews` holds the old pinned host keys and, on cellar,
   `rclone.conf`: copy those back only if you need them.
5. **App files**, straight into place (the node is fresh, nothing to lose):

```bash
./compose.sh --all down
sudo ./backup.sh plan                                  # which paths each app backs up
sudo ./backup.sh restic restore latest --host <node> --tag files --target / \
  --include /srv/data
```

6. **Databases**, from the dumps on cellar (or from restic, tag `dumps`):

```bash
sudo ./backup.sh restic restore latest --tag dumps --target /var/tmp/restore \
  --include /srv/dumps/<node>
ls /var/tmp/restore/srv/dumps/<node>/*/
```

   Start only each database container (`./compose.sh <app> up -d <db service>`),
   then, with the names from that app's `backup` file:

   - Postgres: `docker exec -i <container> pg_restore -U <user> -d <database> --clean --if-exists < <name>.pgdump`
   - SQLite: `gzip -dc <name>.sql.gz | sqlite3 <path>.new`, stop the app, move it over the old file, `chown` it back to the file's owner
   - Mongo: `docker exec -i <container> mongorestore --archive --gzip --drop -u <user> -p <password> --authenticationDatabase admin < <name>.mongo.gz`

7. **Start everything:** `./compose.sh --all up -d`, sign in to each app, then
   `sudo ./backup.sh enable` so it's backed up again tonight.
8. Write it in the runbook: what broke, what came back, what didn't.

---

## B. cellar is gone: the repository from Google Drive

The goal is to put the repository back where the nodes expect it, on a new
cellar at the same address, then do **A** for every node that needs it.

1. **A new cellar.** The bootstrap, as in **A** step 1, with the name `cellar`
   (any machine with room for the repository will do; the address goes with the
   name). Then on it: `sudo ./backup.sh install` and `./setup-secrets.sh`, giving
   it the **old** `RESTIC_PASSWORD`, `RCLONE_CRYPT_PASSWORD` and
   `RCLONE_CRYPT_SALT` from the vault, not new ones.
2. **The account, empty:** `sudo /opt/purrbrews/stacks/backup/restic/repo-setup.sh`.
   It makes `burmilla`, `/srv/backup` and an empty `/srv/backup/restic`. Don't
   run `restic-init.sh`: that would make a new, different repository.
3. **rclone, pointed at Drive.** Easiest: the `rclone.conf` attached in the vault
   (cellar's own, with the Drive token), saved as `/etc/purrbrews/rclone.conf`
   (root, mode 600). If the token has expired, or the attachment isn't there,
   `sudo /opt/purrbrews/stacks/backup/restic/drive-setup.sh` makes it again, with
   `RCLONE_DRIVE_CLIENT_ID` and `RCLONE_DRIVE_CLIENT_SECRET` from the vault; it
   asks you to run `rclone authorize` on americano. The crypt settings must be
   exactly the ones that script uses, or the names won't decrypt.
4. **Check you can read it**, then copy it down:

```bash
R="sudo rclone --config /etc/purrbrews/rclone.conf"
$R lsd drive-crypt:repo                        # data, index, keys, snapshots, config
$R copy drive-crypt:repo /var/tmp/restic-from-drive --transfers 8 -P
```

   `drive-crypt:deleted` has files pruned in the last 30 days, in case you need
   an older snapshot than `repo` still has.
5. **Check the copy** before trusting it:

```bash
sudo restic -r /var/tmp/restic-from-drive snapshots
sudo restic -r /var/tmp/restic-from-drive check --read-data-subset=10%
```

6. **Put it in place**, owned by the account:

```bash
sudo cp -a /var/tmp/restic-from-drive/. /srv/backup/restic/
sudo chown -R burmilla:burmilla /srv/backup/restic
```

7. **Authorize the nodes again.** Every node still has its line in
   `/etc/purrbrews/backup-authorize.txt`: collect them into
   `/opt/purrbrews/stacks/backup/restic/backup.keys`, then `repo-setup.sh` and
   `dump-store-setup.sh` again.
8. On any node: `sudo ./backup.sh doctor`, then `sudo ./backup.sh restic snapshots`
   lists everything. On cellar, `sudo ./backup.sh enable`. Now **A** for whatever
   else is gone (cellar's own apps included), and the nightly Drive sync carries
   on as before: it checks the repository is the same one Drive has.

---

## C. Nothing online: the offline HDD

1. **Boot this stick** (above), or use any PC you trust.
2. Plug in the offline HDD (the dock, or any USB adapter for a 2.5" SATA disk)
   and click it in the file manager, or `lsblk` to find it and
   `sudo mount -o ro /dev/sdXN /mnt`.
3. **Read it where it is**, never write to it:

```bash
restic --no-lock -r /mnt/restic snapshots
restic --no-lock -r /mnt/restic restore latest --host <node> --tag files \
  --target /media/user/<a real disk>/restore --include <path>
```

   `--no-lock` lets restic read a read-only mount.
4. To serve the nodes again, copy `restic/` from the HDD to a new cellar's
   `/srv/backup/restic` and continue from **B** step 5.

The offline copy is as old as its last turn in the dock: check the date of the
newest snapshot, and look for anything newer on Drive once it's back.

---

## After any recovery

- On cellar: `sudo /opt/purrbrews/stacks/backup/restic/restore-test.sh`, and
  again with `--from drive`.
- Anything in the vault that changed (a new key, a rebuilt node's sudo
  password): on americano, `recovery/fill-vault.sh` into A, copy `flask.kdbx` to
  B, `recovery/make-flask.sh --check`.
- A runbook entry, dated, with what you'd do differently.
