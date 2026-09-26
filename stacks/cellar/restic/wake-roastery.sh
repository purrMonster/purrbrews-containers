#!/usr/bin/env bash
#
# wake-roastery.sh: wake roastery before the nodes' nightly backups
# (purrbrews-wake-roastery.timer, 01:25; the nodes start at 01:30 and wait
# up to ten minutes for it). roastery sleeps rather than shutting down so
# this works; the magic packet goes to its USB NIC, whose MAC is
# ROASTERY_WOL_MAC in .env.local (not in git).
#
# The other cellar jobs call the same wake_roastery themselves, so this
# timer only has to be right for the first job of the night.
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."

if wake_roastery 300; then
  echo "roastery is up."
else
  notify "backup: roastery didn't wake" \
    "No SSH from roastery 5 minutes after wake-on-LAN. Tonight's backups will fail. Check its power settings and the USB NIC."
  die "roastery didn't answer within 5 minutes of wake-on-LAN."
fi
