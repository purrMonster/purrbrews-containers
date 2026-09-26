#!/usr/bin/env bash
#
# verify.sh: read part of the repository back and check it
# (purrbrews-backup-verify.timer, the 1st of each month).
#
#   sudo ./restic/verify.sh           checks structure and reads 5% of the data
#   sudo ./restic/verify.sh 100%      reads everything (hours; do it by hand)
#
# restic picks a different 5% each time, so a year of these reads the lot.
# This proves the repository is intact; restore-test.sh proves it's usable.
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: the repository is reached with root's backup key."
SUBSET="${1:-5%}"
[[ "$SUBSET" =~ ^[0-9]+(\.[0-9]+)?%$ ]] || die "usage: verify.sh [percent, e.g. 5%]"

run() {
  restic_env
  wake_roastery || return 1
  "${RESTIC[@]}" --retry-lock 1h check --read-data-subset="$SUBSET"
}

if with_lock run; then
  echo "verify OK ($SUBSET read back)"
else
  notify "backup: repository check FAILED" \
    "restic check --read-data-subset=$SUBSET failed on cellar. Don't prune until it's understood; journalctl -u purrbrews-backup-verify"
  die "repository check failed."
fi
