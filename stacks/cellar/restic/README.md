# restic

The hub of the fleet's backups: cellar is always on, so the jobs that have to run
on time, and be noticed when they don't, live here. Host-native scripts and
systemd timers, not a container. Design and reasoning: runbook, 2026-09-27.

```
every node, 01:30                 cellar                       roastery (sleeps)
  backup.sh nightly                                          C:\purrbrews\restic
   ├─ dump databases ──push──►  /srv/dumps/<node>  ──02:30──►  (SFTP, restic)
   └─ files ─────────────────────────────────────────────────►       │
                                  01:25 wake roastery (WoL)           │
                                  03:00 Sun prune                     │
                                  03:30 drive-sync ◄──────────────────┘
                                        └──► Google Drive, drive-crypt:repo
                                  06:00 check-freshness → ntfy if anything is stale
                                  1st, 04:30 verify (reads 5%)
```

The per-node side is [`stacks/_lib/backup.sh`](../../_lib/backup.sh) (every node's
`./backup.sh`) and each app's `backup` file; see
[stacks/README.md → Backups](../../README.md#backups). This folder is what only
cellar does.

| Script | Timer | Does |
|---|---|---|
| `restic-init.sh` | none, once | creates the repository on roastery |
| `dump-store-setup.sh` | none; again when `dump-store.keys` changes | the `dumps` account and its rrsync-locked keys |
| `drive-setup.sh` | none, once (`--token` to re-authorize) | `/etc/purrbrews/rclone.conf`: roastery, drive, drive-crypt |
| `wake-roastery.sh` | `purrbrews-wake-roastery`, 01:25 | wake-on-LAN, waits for SSH |
| `../backup.sh store` | `purrbrews-backup-store`, 02:30 | the dump store → restic (`--tag dumps`) |
| `restic-prune.sh` | `restic-prune`, Sun 03:00 | forget 7 daily / 4 weekly / 12 monthly, prune |
| `drive-sync.sh` | `drive-sync`, 03:30 | repository → Drive, deletions kept 30 days |
| `check-freshness.sh` | `purrbrews-backup-check`, 06:00 | every snapshot, dump and the Drive copy under 26 h |
| `verify.sh` | `purrbrews-backup-verify`, 1st 04:30 | `restic check --read-data-subset=5%` |
| `restore-test.sh` | none, by hand | restores dumps and sample files, checks them |

Every job needs root (root's backup key and the rclone config are root's), wakes
roastery itself if it's asleep, and reports failures to `NTFY_URL`
(`restic/secrets.env.local`). None of them is switched on yet.

## Tying it together

In this order; each step's check has to pass before the next.

1. **Packages**, on every node: `sudo apt install restic rsync sqlite3`; on cellar
   also `rclone`.
2. **Secrets**: `./setup-secrets.sh` here generates `RESTIC_PASSWORD` and the crypt
   password/salt and asks for the Drive client and `ROASTERY_WOL_MAC`. **Copy
   RESTIC_PASSWORD, RCLONE_CRYPT_PASSWORD and RCLONE_CRYPT_SALT to flask now.**
   On every other node, `./setup-secrets.sh` asks for `RESTIC_PASSWORD`: paste
   cellar's.
3. **Keys**: `sudo ./backup.sh keys` on every node, cellar included. It prints
   one line for roastery and (not on cellar) one for the dump store.
4. **roastery**: the lines go in `stacks/roastery/backup-target/authorized_keys`,
   then `.\setup.ps1` there, elevated ([roastery/README.md](../../roastery/README.md#backup-target)).
   Compare the host key fingerprint it prints with what `keys` pinned.
5. **Dump store**: the other lines go in `restic/dump-store.keys` here, then
   `sudo ./restic/dump-store-setup.sh`.
6. **Repository**: `sudo ./restic/restic-init.sh`.
7. **Check every node**: `sudo ./backup.sh doctor` until it says all good, then
   `sudo ./backup.sh nightly` by hand once. On percolator the first run uploads
   everything: do it with roastery awake and someone at it.
8. **Drive**: the Google API client (below), `sudo ./restic/drive-setup.sh`, then
   `sudo ./restic/drive-sync.sh` by hand (the first upload is slow).
9. **Restore test**: `sudo ./restic/restore-test.sh`, then `--from drive`. Not done
   until both pass.
10. **Timers**: `purrbrews-backup@<node>.timer` on every node
    (`stacks/_lib/systemd/`), and here every `*.timer` in this folder:
    ```sh
    sudo cp restic/*.service restic/*.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now purrbrews-wake-roastery.timer purrbrews-backup-store.timer \
      restic-prune.timer drive-sync.timer purrbrews-backup-check.timer purrbrews-backup-verify.timer
    ```
11. **The morning after**: `sudo ./restic/check-freshness.sh` says everything is
    under 26 h.

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
3. **Authorize:** `sudo ./restic/drive-setup.sh`. cellar has no browser, so it
   asks you to run `rclone authorize` on roastery and paste the JSON back.
4. It checks Drive, makes `drive-crypt:repo`, and checks it can read the
   repository on roastery.

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
- **roastery didn't wake**: its USB NIC's wake setting, or Windows went back to
  sleep; `setup.ps1` sets both. `sudo ./restic/wake-roastery.sh` tries by hand.
- **Restoring something**: `sudo ./backup.sh restic snapshots`, then
  `sudo ./backup.sh restic restore <id> --target /var/tmp/restore --include <path>`
  on any node. Dumps: `pg_restore` for `.pgdump`, `gzip -dc x.sql.gz | sqlite3 new.db`,
  `mongorestore --archive=x.mongo.gz --gzip`.
