#!/usr/bin/env bash
#
# restic-prune.sh — retention, per infrastructure.md §7: all three backup
# targets (cellar's HDD, roastery's mirror, Google Drive) are 1 TB against
# under 512 GB of source, so:
#
#   restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
#
# Run weekly, separately from the nightly backup timer (see
# restic-prune.timer) -- prune is I/O-heavy (rewrites pack files) and has
# no reason to run every single night just because backup does.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$DIR")"
TAG="cellar-restic-prune"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

[[ -f "${STACK_DIR}/.env.local" ]] || { log "FAILED: no .env.local"; exit 1; }
[[ -f "${DIR}/secrets.env.local" ]] || { log "FAILED: no restic/secrets.env.local"; exit 1; }
set -a
source "${STACK_DIR}/.env.local"
source "${DIR}/secrets.env.local"
set +a

REPO="${CELLAR_HDD_MOUNT}/restic-repo"
export RESTIC_PASSWORD
export RESTIC_CACHE_DIR="${DIR}/cache"

log "prune run starting"
if restic -r "$REPO" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune 2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "prune run OK"
else
  log "FAILED: restic forget --prune"
  notify "restic prune FAILED (cellar)" "See journalctl -t ${TAG} or /var/log/${TAG}.log"
  exit 1
fi
