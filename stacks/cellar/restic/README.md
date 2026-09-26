# restic

The fleet's backups. Not a container: a handful of scripts and systemd timers,
all reading the same env files as everything else on cellar.

```
node dumps / data ──► cellar restic (HDD) ──► roastery mirror ──► Google Drive (crypt)
     02:00 backup           04:00 mirror          05:00 sync
     Sun 03:30 prune                                   └──► carafe, quarterly, unplugged
```

| Script | Timer | State |
|---|---|---|
| `restic-init.sh` | none, once by hand | ready |
| `restic-backup.sh` | `restic-backup.timer`, nightly 02:00 | **no sources yet**, fails on purpose |
| `restic-prune.sh` | `restic-prune.timer`, Sundays 03:30 | ready |
| `mirror-to-roastery.sh` | `mirror-to-roastery.timer`, nightly 04:00 | not switched on |
| `drive-sync.sh` | `drive-sync.timer`, nightly 05:00 | not switched on |

A failed run logs to `journalctl -t cellar-restic-*` and, once `NTFY_URL` is set
in `.env.local`, sends an alert.

## Setting it up

```sh
cd /opt/purrbrews/stacks/cellar
./setup-secrets.sh                  # RESTIC_PASSWORD, and asks for the Drive client
sudo mkdir -p /srv/backup           # CELLAR_HDD_MOUNT, the HDD
./restic/restic-init.sh
sudo cp restic/restic-backup.{service,timer} restic/restic-prune.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup.timer restic-prune.timer
```

**Copy `RESTIC_PASSWORD` to flask straight away.** An encrypted backup whose only
key is on the machine that died isn't a backup.

Then add sources to the `SOURCES` list at the top of `restic-backup.sh`. Until
there's one, every run fails on purpose, so an empty repository never looks like
a working backup. Check for real with:

```sh
restic -r /srv/backup/restic-repo snapshots
```

Never point a source at a live Postgres data directory. The database gets dumped
on its own node first, and the dump is what's backed up.

## roastery mirror

Needs, in `.env.local`: `ROASTERY_WOL_MAC` (the USB dongle, not the onboard NIC),
`ROASTERY_SSH_HOST`, `ROASTERY_MIRROR_PATH`, and an SSH key from the ops user to
roastery. Then install and enable `mirror-to-roastery.{service,timer}` the same way
as above.

## Google Drive sync

rclone gets its own Google API client: the shared default is the biggest cause of
`403 userRateLimitExceeded`, since every rclone user shares its quota. One-time
setup; the same client works for any other node later.

1. **Make the client** at [console.cloud.google.com](https://console.cloud.google.com):
   - a new project (say `purrbrews-restic`), with the **Google Drive API** enabled;
   - *OAuth consent screen*: **External**, your own email, yourself as a **test
     user**. Leave it in *Testing*: only you use it, and rclone refreshes the
     7-day tokens itself as long as it keeps running;
   - *Credentials → Create credentials → OAuth client ID → Desktop app*, and copy
     the ID and secret (the secret is only shown once).

2. **Paste them in:** `./setup-secrets.sh` asks for `RCLONE_DRIVE_CLIENT_ID` and
   `RCLONE_DRIVE_CLIENT_SECRET` and renders `restic/rclone.conf`.

3. **Authorize the token.** It needs a browser and cellar is headless. Either
   tunnel the callback port:
   ```sh
   ssh -L 53682:localhost:53682 barista@cellar
   cd /opt/purrbrews/stacks/cellar
   rclone config reconnect drive: --config restic/rclone.conf
   ```
   and open the `http://127.0.0.1:53682/auth?...` link it prints on your own
   machine; or run `rclone authorize "drive" '<client id>' '<client secret>'` on a
   machine with a browser and paste the JSON it prints into
   `rclone config reconnect drive: --config restic/rclone.conf --auth-no-open-browser`.

4. **Set the crypt passwords** (say `y` to a random one each time):
   ```sh
   rclone config password drive-crypt password  --config restic/rclone.conf
   rclone config password drive-crypt password2 --config restic/rclone.conf
   ```
   **Both go to flask too.** Lose them and everything already on Drive is
   unreadable; they aren't stored anywhere else.

5. **Check it:** `rclone lsd drive-crypt: --config restic/rclone.conf`. An empty
   listing is good. An OAuth error means step 3 again; a `403` usually means
   `rclone.conf` isn't using your client (re-render).

6. **Switch it on** once there's a real local backup to send:
   ```sh
   sudo cp restic/drive-sync.{service,timer} /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now drive-sync.timer
   ```

A single Google account is its own single point of failure. The small critical set
(Vaultwarden export, Paperless documents, every node's `.env.local`, about 20 GB)
should live somewhere else as well.
