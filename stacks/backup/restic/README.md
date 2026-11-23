# restic

The hub of the fleet's backups: cellar is always on, so the jobs that have to run
on time, and be noticed when they don't, live here. Host-native scripts and
systemd timers, not a container. Design and reasoning: runbook, 2026-09-27.

```
every node, 01:30                 cellar
  backup.sh nightly
   ├─ dump databases ──push──►  /srv/dumps/<node>   (account dumps, rrsync)
   │                                  │ 02:30 store
   └─ files ────────SFTP──────►  /srv/backup/restic  (account burmilla, chrooted)
                                       │ 03:00 Sun prune
                                  03:30 drive-sync (reads the folder by path)
                                        └──► Google Drive, drive-crypt:repo
                                  06:00 check-freshness → ntfy if anything is stale
                                  1st, 04:30 verify (reads 5%)
```

Since the 2026-11 rebuild the repository is on cellar's NVMe too; it was on
roastery, a Windows workstation that had to be woken for every job (retired,
runbook 2026-11-16). Every node writes it over SFTP through one account, cellar
included, so all its files belong to that account. Only `drive-sync.sh` reads it
straight off the disk.

The per-node side is [`stacks/_lib/backup.sh`](../../_lib/backup.sh) (every node's
`./backup.sh`) and each app's `backup` file; see
[stacks/README.md → Backups](../../README.md#backups). This folder is what only
cellar does.

| Script | Timer | Does |
|---|---|---|
| `repo-setup.sh` | none; again when `backup.keys` changes | the repository's SFTP-only account, chrooted to `BACKUP_REPO_ROOT`, with each node's key pinned to its address |
| `dump-store-setup.sh` | none; again when `backup.keys` changes | the `dumps` account and its rrsync-locked keys |
| `restic-init.sh` | none, once | creates the repository, through the account |
| `drive-setup.sh` | none, once (`--token` to re-authorize) | `/etc/purrbrews/rclone.conf`: drive, drive-crypt |
| `../backup.sh store` | `purrbrews-backup-store`, 02:30 | the dump store → restic (`--tag dumps`) |
| `restic-prune.sh` | `restic-prune`, Sun 03:00 | forget 7 daily / 4 weekly / 12 monthly, prune |
| `drive-sync.sh` | `drive-sync`, 03:30 | repository → Drive, deletions kept 30 days. Refuses when the repository folder has no repository, or a different one than Drive (its `config` file differs), so a wiped or re-initialised disk can't be mirrored over the offsite copy |
| `check-freshness.sh` | `purrbrews-backup-check`, 06:00 | every snapshot, dump and the Drive copy under 26 h |
| `verify.sh` | `purrbrews-backup-verify`, 1st 04:30 | `restic check --read-data-subset=5%` |
| `restore-test.sh` | none, by hand | restores dumps and sample files, checks them |

Every job needs root (root's backup key and the rclone config are root's) and
reports failures to `NTFY_URL` (`restic/secrets.env.local`). In the old fleet
they ran from 2026-09-28; in this one, from the night phase 4 of
[the migration plan](../../../docs/migration-plan.md) finishes.

## Where it lives on cellar

| What | Where | Owner |
|---|---|---|
| The chroot (`BACKUP_REPO_ROOT`, stacks/fleet.env) | `/srv/backup` | root, 755: sshd insists |
| The repository (the path in `BACKUP_REPOSITORY`) | `/srv/backup/restic`, seen as `/restic` over SFTP | `burmilla`, 700 |
| The account's keys | `/var/lib/burmilla/.ssh/authorized_keys`, rebuilt by `repo-setup.sh` | `burmilla`, 600 |
| The sshd rules | `/etc/ssh/sshd_config.d/20-purrbrews-repo.conf` | root |

A key in that file can do one thing: SFTP inside `/srv/backup`, from its node's
address. It can't open a shell, forward a port or see another folder. It can
delete snapshots, which no SFTP setup can stop; Drive's 30-day undo is the answer
to that.

## Tying it together

Commands below run from the node's folder, `/opt/purrbrews/nodes/<node>`; the
hub's scripts live in `stacks/backup/restic`, hence `../../stacks/backup/restic/`.
The node folders have no `restic/` of their own (they did in the old layout).

`sudo ./backup.sh install` and `sudo ./backup.sh enable` do most of it on each
node; the rest is what only a person can do (sudo, a Google sign-in, the recovery
kit). In this order:

1. **cellar**: `sudo ./backup.sh install` (packages, cellar's key, the units, not
   enabled), then `./setup-secrets.sh`: it makes `RESTIC_PASSWORD` and the crypt
   password and salt, and asks for the Drive client. **Copy RESTIC_PASSWORD,
   RCLONE_CRYPT_PASSWORD and RCLONE_CRYPT_SALT to the recovery kit now.**
2. **Every other node**: `sudo ./backup.sh install`, and `./setup-secrets.sh`,
   which asks for cellar's `RESTIC_PASSWORD`. Each prints one line,
   `<node> from="<ip>" ssh-ed25519 …` (also in `/etc/purrbrews/backup-authorize.txt`).
3. **Authorize them on cellar**: those lines into `../../stacks/backup/restic/backup.keys` (copy
   `backup.keys.example` beside it), then `sudo ../../stacks/backup/restic/repo-setup.sh` and
   `sudo ../../stacks/backup/restic/dump-store-setup.sh`. cellar's own key needs no line.
4. **Repository**: `sudo ../../stacks/backup/restic/restic-init.sh` on cellar.
5. **Every node, cellar first**: `sudo ./backup.sh enable`: doctor, one backup
   now, then its timers (on cellar, every timer in this folder too). Every app
   starts empty in this fleet, so the first runs are small.
6. **Drive**: the Google API client (below), `sudo ../../stacks/backup/restic/drive-setup.sh`, then
   `sudo ../../stacks/backup/restic/drive-sync.sh` by hand once. Until then the nightly Drive sync
   and the morning check will complain, rightly. If an old fleet's copy is still
   in `drive-crypt:repo`, move it aside first: the sync refuses to replace a
   different repository, by design.
7. **Restore test**: `sudo ../../stacks/backup/restic/restore-test.sh`, then `--from drive`. Not done
   until both pass.
8. **The morning after**: `sudo ../../stacks/backup/restic/check-freshness.sh` says everything is
   under 26 h.

`sudo ./backup.sh disable` turns a node's timers off again.

## Google Drive

rclone gets its own Google API client: the shared default is the biggest cause of
`403 userRateLimitExceeded`, since every rclone user shares its quota.

1. **Make the client** at [console.cloud.google.com](https://console.cloud.google.com):
   - a new project (say `purrbrews-backups`) with the **Google Drive API** enabled;
   - *OAuth consent screen*: **External**, your own email, then **Publish app**
     (In production). An app left in *Testing* gets refresh tokens that expire
     after 7 days, and the nightly sync would stop a week in. Unverified is fine
     for an app only you use; Google warns once at sign-in;
   - *Credentials → Create credentials → OAuth client ID → Desktop app*; copy the
     ID and secret (the secret is shown once).
2. **Paste them in:** `./setup-secrets.sh` asks for `RCLONE_DRIVE_CLIENT_ID` and
   `RCLONE_DRIVE_CLIENT_SECRET`.
3. **Authorize:** `sudo ../../stacks/backup/restic/drive-setup.sh`. cellar has no browser, so it
   asks you to run `rclone authorize` on americano and paste the JSON back.
4. It checks Drive, makes `drive-crypt:repo`, and checks the repository is in
   its folder.

The rclone config is `/etc/purrbrews/rclone.conf`, not a rendered template:
rclone writes the refreshed token back into it, and a re-render would throw that
away. It's backed up with cellar's settings.

A single Google account is its own single point of failure. The small critical
set (Vaultwarden, Paperless, every node's settings) should live somewhere else as
well, one day.

## When something's wrong

- **A node's backup failed**: `journalctl -u purrbrews-backup@<node>` there;
  `sudo ./backup.sh doctor` says what's missing.
- **"repository is already locked"**: a run crashed mid-way. After making sure
  nothing is running, `sudo ./backup.sh restic unlock` (removes only stale locks).
- **A node can't reach the repository**: `sudo ./backup.sh doctor` there. "Doesn't
  open" usually means its line isn't in `backup.keys` yet, or `repo-setup.sh`
  wasn't run after it was added, or the node's address changed (the line is
  pinned to it). On cellar, `journalctl -u ssh` shows why a key was refused.
- **Restoring something**: `sudo ./backup.sh restic snapshots`, then
  `sudo ./backup.sh restic restore <id> --target /var/tmp/restore --include <path>`
  on any node. Dumps: `pg_restore` for `.pgdump`, `gzip -dc x.sql.gz | sqlite3 new.db`,
  `mongorestore --archive=x.mongo.gz --gzip`.
