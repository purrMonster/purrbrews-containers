#!/usr/bin/env bash
#
# drive-sync.sh: the offsite copy (drive-sync.timer, 03:30). rclone copies
# the repository from roastery (SFTP) to Google Drive through the crypt
# remote, so Google sees neither the contents (restic encrypts those) nor
# the file names (crypt hides those). Setup: drive-setup.sh.
#
# It's a sync, so prune's deletions carry over. What a sync deletes or
# overwrites is moved to drive-crypt:deleted/<date> instead of vanishing,
# and kept 30 days. That's the undo for the one thing SFTP can't stop: a
# node's key deleting snapshots on roastery. Drive's copy of them outlives
# the damage by a month.
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: the rclone config and the backup key are root's."
command -v rclone >/dev/null || die "rclone isn't installed (apt install rclone)."
RCLONE_CONF="$BACKUP_ETC/rclone.conf"
[[ -f "$RCLONE_CONF" ]] || die "no $RCLONE_CONF; run ./restic/drive-setup.sh first."
KEEP_DELETED=30d
STATE=/var/lib/purrbrews
rc() { rclone --config "$RCLONE_CONF" "$@"; }

run() {
  restic_env
  wake_roastery || return 1
  # A sync in the middle of a backup or prune copies a half-written
  # repository. restic's own locks say whether anyone is writing; wait up to
  # an hour for them to clear. A lock left by a crashed run keeps failing
  # this until someone runs `sudo ./backup.sh restic unlock` here.
  local waited=0 locks
  while :; do
    locks="$("${RESTIC[@]}" list locks --no-lock 2>/dev/null | wc -l)" || locks=0
    [[ "$locks" -eq 0 ]] && break
    (( waited >= 3600 )) && { warn "the repository has been locked for an hour; syncing anyway would copy a half-written state"; return 1; }
    echo "repository locked ($locks lock(s)); waiting"
    sleep 60; waited=$((waited + 60))
  done

  rc sync "roastery:$REPO_PATH" drive-crypt:repo \
    --backup-dir "drive-crypt:deleted/$(date +%F)" \
    --transfers 4 --checkers 8 --tpslimit 10 \
    --drive-chunk-size 64M --drive-use-trash=false \
    --stats 5m --stats-one-line -v
  # Age out the undo copies.
  rc delete drive-crypt:deleted --min-age "$KEEP_DELETED" --rmdirs 2>/dev/null || true
}

if with_lock run; then
  install -d -m 755 "$STATE"
  touch "$STATE/drive-sync.ok"
  echo "drive sync OK"
else
  notify "backup: Drive sync FAILED" "The offsite copy wasn't updated tonight. journalctl -u drive-sync on cellar"
  die "drive sync failed."
fi
