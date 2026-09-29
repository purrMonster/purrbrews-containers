# RECOVERY

You're reading this because something is gone. Take it slowly: nothing below
deletes anything, and every restore goes into a scratch folder first unless it
says otherwise. This file lives on each flask stick and in the repo at
`stacks/roastery/flask/RECOVERY.md`; the repo's copy is the current one, if
GitHub is still there for you.

**Where the backups are** (newest first):

| Copy | Where | Needs |
|---|---|---|
| The repository | roastery, `C:\purrbrews\restic` (later `D:\purrbrews\restic`) | `RESTIC_PASSWORD` |
| Google Drive | `drive-crypt:repo` (the folder `purrbrews-restic`, names encrypted) | the Google account, `RCLONE_CRYPT_PASSWORD`, `RCLONE_CRYPT_SALT`, `RESTIC_PASSWORD` |
| Offline HDD | the disk labelled `PB-OFFLINE`, folder `restic\` | `RESTIC_PASSWORD` |
| Database dumps | cellar, `/srv/dumps/<node>/` | nothing; they're plain files (and in all three above) |

Every secret is in `flask.kdbx` on this stick. Tier 1 (the three above) is also
on the paper.

**Pick your case:**

- One node is gone, roastery is fine → **A**
- roastery (or its disk) is gone → **B**, then **A** for each node
- No roastery, no Drive, no internet → **C**, then **A**

---

## Before any case: tools and the vault

**On Windows** (roastery or any PC you trust): `tools\windows-amd64\` has
`restic.exe`, `rclone.exe` and `KeePassXC\KeePassXC.exe`. Run them from the stick.

**On a PC you don't trust, or with nothing working: boot this stick.**

1. Plug it in, power on, open the boot menu (F12, F11, F8 or Esc, depending on
   the PC) and pick the USB stick.
2. First time on a PC with Secure Boot: Ventoy shows a blue *Verification
   failed* screen. Choose **Enroll key from disk** → `VTOYEFI` →
   `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` → Continue → Yes → Reboot, and boot the
   stick again. (Or turn Secure Boot off in the firmware for now.)
3. In Ventoy's menu pick `debian-live-…-xfce.iso` → *Boot in normal mode* →
   *Live system*. It needs no password; if something asks, the user is `user`,
   the password `live`.
4. **The kit mounts itself** at `/mnt/flask`, read-only, and a file manager opens
   on it (Ventoy injects a small script at boot; `make-flask.ps1` puts it there).
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

On Windows: `$env:RESTIC_PASSWORD = Read-Host -MaskInput` (PowerShell 7) or
paste it into `$env:RESTIC_PASSWORD = '...'` and close the window after.

---

## A. One node is gone; roastery still has the repository

This is the normal case, and you don't need to boot the stick for it.

1. **Rebuild the node** from the repo: `README.md` → bootstrap, then
   `purrbrews-init` for that node, then `./setup-secrets.sh`. Don't start its
   apps yet.
2. **Let it reach roastery again.** A new install has a new backup key:
   `sudo ./backup.sh install` on the node prints the lines to authorize (also in
   `/etc/purrbrews/backup-authorize.txt`). Put its `roastery` line in
   `stacks/roastery/backup-target/authorized_keys` on roastery and run
   `.\setup.ps1 -KeysOnly` there, elevated. If the node was cellar, the other
   nodes' `store` lines go into its `restic/dump-store.keys` again, then
   `sudo ./restic/dump-store-setup.sh`.
3. **See what there is:** `sudo ./backup.sh restic snapshots --host <node>`.
4. **Settings first**, into a scratch folder, then copied into place:

```bash
sudo ./backup.sh restic restore latest --host <node> --tag files \
  --target /var/tmp/restore --include /opt/purrbrews --include /etc/purrbrews
sudo ls -la /var/tmp/restore/opt/purrbrews/stacks/<node>/        # check before copying
sudo cp -a /var/tmp/restore/opt/purrbrews/.env /opt/purrbrews/.env
sudo cp -a /var/tmp/restore/opt/purrbrews/stacks/<node>/.env.local /opt/purrbrews/stacks/<node>/
for f in /var/tmp/restore/opt/purrbrews/stacks/<node>/*/secrets.env.local; do
  sudo cp -a "$f" "/opt/purrbrews/stacks/<node>/$(basename "$(dirname "$f")")/"; done
```

   These carry the Tier 2 keys that match the data, so the data restored next
   can be read. `/etc/purrbrews` holds the old pinned host keys and, on cellar,
   `rclone.conf`: copy those back only if you need them (cellar: yes).
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

## B. roastery is gone: the repository from Google Drive

The goal is to put the repository back where the nodes expect it, then do **A**.

1. **A Windows PC to be the new roastery.** Clone the repo, then
   `stacks\roastery\backup-target\setup.ps1`, elevated. It makes the `restic`
   account, `C:\purrbrews\restic` and the SSH server.
2. **rclone, pointed at Drive.** Easiest: the `rclone.conf` attached in the vault
   (cellar's own, with the Drive token). Save it as `rclone.conf` next to
   `rclone.exe` and add `--config rclone.conf` to the commands below. Its
   `roastery` remote is useless now; `drive` and `drive-crypt` are what matter.
   If the token has expired, or the attachment isn't there, make the two remotes
   again (Google sign-in opens in the browser):

```powershell
.\rclone.exe config create drive drive scope=drive client_id=<RCLONE_DRIVE_CLIENT_ID> client_secret=<RCLONE_DRIVE_CLIENT_SECRET>
.\rclone.exe config create drive-crypt crypt remote=drive:purrbrews-restic filename_encryption=standard directory_name_encryption=true password=<RCLONE_CRYPT_PASSWORD> password2=<RCLONE_CRYPT_SALT> --obscure
```

   These settings must match `stacks/cellar/restic/drive-setup.sh` exactly, or
   the names won't decrypt. (Without the client ID, leave `client_id` and
   `client_secret` out: rclone's shared client works for a one-off download.)
3. **Check you can read it**, then copy it down:

```powershell
.\rclone.exe lsd drive-crypt:repo                       # data, index, keys, snapshots, config
.\rclone.exe copy drive-crypt:repo C:\restic-from-drive --transfers 8 -P
```

   `drive-crypt:deleted` has files pruned in the last 30 days, in case you need
   an older snapshot than `repo` still has.
4. **Check the copy** before trusting it:

```powershell
.\restic.exe -r C:\restic-from-drive snapshots
.\restic.exe -r C:\restic-from-drive check --read-data-subset=10%
```

5. **Put it in place** and let `setup.ps1` fix its permissions:

```powershell
robocopy C:\restic-from-drive C:\purrbrews\restic /E
.\setup.ps1                                             # again, elevated
```

6. **Authorize the nodes again.** The new roastery's `authorized_keys` is empty;
   every node still has its lines in `/etc/purrbrews/backup-authorize.txt`.
   Collect the `roastery` lines into `stacks/roastery/backup-target/authorized_keys`,
   then `.\setup.ps1 -KeysOnly`. If roastery's address changed, update
   `ROASTERY_LAN_IP` and `BACKUP_REPOSITORY` in `stacks/fleet.env` and push.
7. On any node: `sudo ./backup.sh restic snapshots` lists everything. Now **A**
   for whatever else is gone, and cellar's `drive-sync` carries on as before.

---

## C. Nothing online: the offline HDD

1. **Boot this stick** (above), or use any PC you trust.
2. Plug in the `PB-OFFLINE` disk and click it in the file manager: it mounts as
   `/media/user/PB-OFFLINE` (NTFS). If it doesn't, `sudo mount -t ntfs3 -o ro
   /dev/sdXN /mnt`, with the partition from `lsblk`.
3. **Read it where it is**, never write to it:

```bash
restic -r /media/user/PB-OFFLINE/restic snapshots
restic -r /media/user/PB-OFFLINE/restic restore latest --host <node> --tag files \
  --target /media/user/<a real disk>/restore --include <path>
```

   restic needs to write its cache and locks; `--no-lock` lets it read a
   read-only mount (`restic --no-lock -r ... snapshots`).
4. To serve the nodes again, copy `restic\` from the HDD to the new roastery's
   `C:\purrbrews\restic` and continue from **B** step 4.

The offline copy is as old as its last monthly sync: check the date of the newest
snapshot, and look for anything newer on cellar's dump store or on Drive once
they're back.

---

## After any recovery

- `sudo ./restic/restore-test.sh` on cellar, and `--from drive`.
- Anything in the vault that changed (a new key, a rebuilt node's sudo password):
  update `flask.kdbx` on A, copy it to B, `.\make-flask.ps1 -Check`.
- A runbook entry, dated, with what you'd do differently.
