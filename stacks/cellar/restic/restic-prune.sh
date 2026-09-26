#!/usr/bin/env bash
#
# restic-prune.sh: weekly retention (restic-prune.timer). Every copy of the
# repository has about a terabyte for well under half that of source, so:
# 7 daily, 4 weekly, 12 monthly. Weekly rather than nightly because prune
# rewrites pack files and there's no reason to pay that I/O every night.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
TAG="cellar-restic-prune"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

[[ -f "$ENV_LOCAL" && -f "$DIR/secrets.env.local" ]] || { log "FAILED: run ../setup-secrets.sh first"; exit 1; }
export_env restic
REPO="${CELLAR_HDD_MOUNT:?}/restic-repo"
export RESTIC_PASSWORD
export RESTIC_CACHE_DIR="$DIR/cache"

log "prune run starting"
if restic -r "$REPO" forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune 2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "prune run OK"
else
  log "FAILED: restic forget --prune"
  notify "restic prune FAILED (cellar)" "See journalctl -t $TAG or /var/log/${TAG}.log"
  exit 1
fi
