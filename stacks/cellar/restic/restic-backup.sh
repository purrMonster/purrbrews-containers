#!/usr/bin/env bash
#
# restic-backup.sh — pulls each node's data into the local restic
# repository on cellar's HDD. Step one of infrastructure.md §7's chain:
#
#   percolator (dumps DBs to its own SATA SSD)
#        -> cellar (this script, restic into the HDD repo)         <- here
#        -> roastery (mirror-to-roastery.sh)
#        -> Google Drive (drive-sync.sh)
#        -> carafe (quarterly, manual, unplugged)
#
# "The schedule lives on cellar, not on roastery" (§7) — this and
# restic-prune.sh are the schedule; see restic-backup.timer.
#
# Never backs up a hot Postgres/etc file directly (§7's own rule) — every
# source below is either a static dump directory or plain files, never a
# live database's data directory. percolator's dump step is that node's
# own responsibility once it's migrated into this repo; nothing here
# triggers it.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$DIR")"
TAG="cellar-restic-backup"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  # Best-effort — ntfy lives on sieve (infrastructure.md §4); if it's down
  # or NTFY_URL isn't set yet, a failed curl here must never fail the
  # backup job itself.
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
export RESTIC_CACHE_DIR="${DIR}/cache"   # on the NVMe (this stack directory's
                                          # disk, per infrastructure.md §3 --
                                          # "restic cache on NVMe, repository
                                          # on HDD") -- keeps the HDD's
                                          # random-I/O-heavy cache traffic
                                          # off the spinning disk itself.

if ! restic -r "$REPO" snapshots >/dev/null 2>&1; then
  log "FAILED: repository doesn't exist at ${REPO} -- run ./restic-init.sh first"
  notify "restic backup FAILED (cellar)" "Repository missing -- run restic-init.sh."
  exit 1
fi

# --- Sources ---------------------------------------------------------------
# One `restic backup` call per source, same "REPLACE_ME until the source
# actually has something worth backing up" discipline the old mirror.sh
# used -- but unlike that script, each line here is a real, runnable
# restic invocation, not a function definition nobody called. Uncomment
# and fill in as each node's dump/data directory is confirmed to exist
# (SSH key from cellar's runtime user to each source needs to be set up
# first, ssh-copy-id, same one-time manual step the old mirror.sh
# documented).
#
#   restic -r "$REPO" backup /mnt/percolator-dumps --tag percolator --host percolator
#   restic -r "$REPO" backup /mnt/sieve-data        --tag sieve      --host sieve
#   restic -r "$REPO" backup /mnt/mochapot-data     --tag mochapot   --host mochapot
#
# cellar's own /srv/data (Komodo's mongo, Scrutiny's config/influxdb, Diun's
# state) is worth including too, once this node has run for a while:
#
#   restic -r "$REPO" backup /srv/data --tag cellar --host cellar
# -----------------------------------------------------------------------

SOURCES_CONFIGURED=0   # flip to 1 once at least one restic backup line above is live

if [[ "$SOURCES_CONFIGURED" -eq 0 ]]; then
  log "FAILED: no sources configured -- no backup was taken; see the Sources section"
  exit 1
fi

log "backup run starting"
if restic -r "$REPO" backup /srv/data --tag cellar --host cellar 2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "backup run OK"
else
  log "FAILED: restic backup"
  notify "restic backup FAILED (cellar)" "See journalctl -t ${TAG} or /var/log/${TAG}.log"
  exit 1
fi
