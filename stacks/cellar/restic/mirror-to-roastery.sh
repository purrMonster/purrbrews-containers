#!/usr/bin/env bash
#
# mirror-to-roastery.sh — step three of infrastructure.md §7's chain:
# cellar pushes a mirror of the restic repository to roastery's SATA
# drive, waking roastery over WoL first if it's asleep (§4: "roastery
# sleeps rather than shuts down", exactly so this can reach it). roastery
# holds the SECOND copy, not the primary -- cellar's own HDD repo is what
# a real restore reads from (§7: "roughly forty minutes on gigabit" vs.
# waiting on a cloud download).
#
# Needs an SSH key from cellar's runtime user to roastery, and roastery's
# WoL MAC (the USB dongle, not its onboard NIC -- see the 2026-09-15
# private notes for the confirmed MAC, C8:4D:44:27:B1:E5, kept out of this
# tracked file per this repo's "no real MACs in git" rule -- put it in
# .env.local as ROASTERY_WOL_MAC instead, not added to local.env.example
# until this script is actually wired up).
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$DIR")"
TAG="cellar-restic-mirror"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

[[ -f "${STACK_DIR}/.env.local" ]] || { log "FAILED: no .env.local"; exit 1; }
set -a
source "${STACK_DIR}/.env.local"
set +a

: "${ROASTERY_WOL_MAC:?Set ROASTERY_WOL_MAC in .env.local before enabling this script}"
: "${ROASTERY_SSH_HOST:?Set ROASTERY_SSH_HOST (user@host) in .env.local before enabling this script}"
: "${ROASTERY_MIRROR_PATH:?Set ROASTERY_MIRROR_PATH (destination dir on roastery) in .env.local before enabling this script}"

REPO="${CELLAR_HDD_MOUNT}/restic-repo"

log "waking roastery (${ROASTERY_WOL_MAC})"
command -v wakeonlan >/dev/null 2>&1 || { log "FAILED: wakeonlan not installed (apt install wakeonlan)"; exit 1; }
wakeonlan "$ROASTERY_WOL_MAC"

log "waiting for roastery to answer SSH (up to 5 min)"
for _ in $(seq 1 30); do
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$ROASTERY_SSH_HOST" true 2>/dev/null && break
  sleep 10
done
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$ROASTERY_SSH_HOST" true 2>/dev/null; then
  log "FAILED: roastery didn't come up within 5 min"
  notify "restic mirror FAILED (cellar -> roastery)" "roastery never answered SSH after WoL."
  exit 1
fi

log "syncing ${REPO} -> ${ROASTERY_SSH_HOST}:${ROASTERY_MIRROR_PATH}"
if rsync -az --delete "${REPO}/" "${ROASTERY_SSH_HOST}:${ROASTERY_MIRROR_PATH}/" 2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "mirror run OK"
else
  log "FAILED: rsync to roastery"
  notify "restic mirror FAILED (cellar -> roastery)" "See journalctl -t ${TAG} or /var/log/${TAG}.log"
  exit 1
fi
# --delete here is deliberate and different from the old backup-mirror's
# append-only rsync: this mirror is meant to be a byte-identical second
# copy of the restic repository (which does its own pruning via `restic
# forget --prune`), not an independent append-only archive. restic's own
# encryption and content-addressed pack files are the integrity guarantee
# here, not rsync's flags.
