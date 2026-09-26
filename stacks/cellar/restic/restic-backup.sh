#!/usr/bin/env bash
#
# restic-backup.sh: nightly, pulls each source into the restic repository on
# cellar's HDD (restic-backup.timer). It's the first link in the chain:
#
#   node dumps/data → cellar restic (this) → roastery mirror → Google Drive
#                                          → carafe, quarterly, unplugged
#
# The schedule lives on cellar because cellar is always on; a job that
# didn't run should be noticed from a box that's awake, not fail quietly on
# roastery while it sleeps.
#
# Never point a source at a live database's data directory. Postgres gets
# dumped first (by its own node) and the dump is what's backed up here.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
TAG="cellar-restic-backup"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {  # best effort; a missing ntfy must never fail the backup itself
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

# ── Sources ──────────────────────────────────────────────────────────────────
# "<path> <tag>", one per source. Still empty: the dump job on percolator
# and the SSH access from cellar to each node don't exist yet (runbook
# backlog). Until there's at least one, every run fails loudly on purpose.
SOURCES=(
  # "/mnt/percolator-dumps percolator"
  # "/srv/data cellar"
)

[[ -f "$ENV_LOCAL" && -f "$DIR/secrets.env.local" ]] || { log "FAILED: run ../setup-secrets.sh first"; exit 1; }
export_env restic
REPO="${CELLAR_HDD_MOUNT:?}/restic-repo"
export RESTIC_PASSWORD
# The cache sits on the NVMe with this checkout, keeping its random I/O off the HDD.
export RESTIC_CACHE_DIR="$DIR/cache"

if ! restic -r "$REPO" snapshots >/dev/null 2>&1; then
  log "FAILED: no repository at $REPO; run ./restic-init.sh first"
  notify "restic backup FAILED (cellar)" "Repository missing; run restic-init.sh."
  exit 1
fi
if [[ ${#SOURCES[@]} -eq 0 ]]; then
  log "FAILED: no sources configured, so no backup was taken (see SOURCES)"
  exit 1
fi

status=0
for source in "${SOURCES[@]}"; do
  read -r path tag <<< "$source"
  log "backing up $path ($tag)"
  if ! restic -r "$REPO" backup "$path" --tag "$tag" --host "$tag" 2>&1 | tee -a "/var/log/${TAG}.log"; then
    log "FAILED: restic backup of $path"
    status=1
  fi
done
if [[ $status -ne 0 ]]; then
  notify "restic backup FAILED (cellar)" "See journalctl -t $TAG or /var/log/${TAG}.log"
  exit 1
fi
log "backup run OK"
