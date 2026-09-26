#!/usr/bin/env bash
#
# mirror-to-roastery.sh: the second copy. Wakes roastery (it sleeps, it
# doesn't shut down, exactly so this works), then rsyncs the repository to
# its SATA drive. A restore still reads from cellar's HDD; this is for when
# cellar is the thing that died.
#
# Not switched on yet. Needs, in .env.local: ROASTERY_WOL_MAC (the USB
# dongle's MAC, not the onboard NIC's; it stays out of git),
# ROASTERY_SSH_HOST and ROASTERY_MIRROR_PATH, plus an SSH key from the ops
# user to roastery.
#
# --delete is deliberate: this is a byte-for-byte copy of a repository that
# prunes itself, not an append-only archive. restic's content-addressed,
# encrypted packs are the integrity check, not rsync's flags.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
TAG="cellar-restic-mirror"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

[[ -f "$ENV_LOCAL" ]] || { log "FAILED: no .env.local"; exit 1; }
export_env
: "${ROASTERY_WOL_MAC:?set ROASTERY_WOL_MAC in .env.local before enabling this}"
: "${ROASTERY_SSH_HOST:?set ROASTERY_SSH_HOST (user@host) in .env.local before enabling this}"
: "${ROASTERY_MIRROR_PATH:?set ROASTERY_MIRROR_PATH in .env.local before enabling this}"
REPO="${CELLAR_HDD_MOUNT:?}/restic-repo"

command -v wakeonlan >/dev/null || { log "FAILED: wakeonlan isn't installed (apt install wakeonlan)"; exit 1; }
log "waking roastery ($ROASTERY_WOL_MAC)"
wakeonlan "$ROASTERY_WOL_MAC"

log "waiting up to 5 minutes for roastery to answer SSH"
up=0
for _ in $(seq 1 30); do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "$ROASTERY_SSH_HOST" true 2>/dev/null; then up=1; break; fi
  sleep 10
done
if [[ $up -eq 0 ]]; then
  log "FAILED: roastery didn't come up within 5 minutes"
  notify "restic mirror FAILED (cellar -> roastery)" "roastery never answered SSH after WoL."
  exit 1
fi

log "syncing $REPO -> $ROASTERY_SSH_HOST:$ROASTERY_MIRROR_PATH"
if rsync -az --delete "$REPO/" "$ROASTERY_SSH_HOST:$ROASTERY_MIRROR_PATH/" 2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "mirror run OK"
else
  log "FAILED: rsync to roastery"
  notify "restic mirror FAILED (cellar -> roastery)" "See journalctl -t $TAG or /var/log/${TAG}.log"
  exit 1
fi
