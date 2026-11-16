#!/usr/bin/env bash
#
# restic-prune.sh: weekly retention for the whole repository
# (restic-prune.timer, Sundays 03:00: after the store backup, before the
# Drive sync, so Drive gets the pruned repository).
#
# One host prunes, and it's this one: two prunes, or a prune and a backup,
# fighting over the lock is how a night gets lost. Snapshots are grouped by
# host and tag, so each node's files and the dump store age separately.
#
# Keeps 7 daily, 4 weekly, 12 monthly. At ~100 GB of source that's a small
# multiple of it on roastery's NVMe.
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: the repository is reached with root's backup key."

run() {
  restic_env
  wake_roastery || return 1
  # --retry-lock: a node still on its first, hours-long backup holds a lock.
  "${RESTIC[@]}" --retry-lock 1h forget --group-by host,tags \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
}

if with_lock run; then
  echo "prune OK"
else
  notify "backup: prune FAILED" "journalctl -u restic-prune on cellar"
  die "prune failed."
fi
