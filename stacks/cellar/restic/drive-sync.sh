#!/usr/bin/env bash
#
# drive-sync.sh: the offsite copy. rclone syncs the repository to Google
# Drive through a crypt remote, so Google sees neither the contents (restic
# encrypts those) nor the file names (crypt hides those).
#
# Not switched on yet; restic/README.md walks through the one-time Google
# API client and OAuth setup. Drive throttles thousands of small objects
# hard, hence --tpslimit and the big chunk size.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
TAG="cellar-restic-drive-sync"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

[[ -f "$ENV_LOCAL" ]] || { log "FAILED: no .env.local"; exit 1; }
export_env
command -v rclone >/dev/null || { log "FAILED: rclone isn't installed"; exit 1; }
[[ -f "$DIR/rclone.conf" ]] || { log "FAILED: rclone.conf isn't rendered; see restic/README.md"; exit 1; }
REPO="${CELLAR_HDD_MOUNT:?}/restic-repo"

log "sync run starting"
if rclone sync "$REPO" drive-crypt: \
    --config "$DIR/rclone.conf" \
    --tpslimit=10 --drive-chunk-size=256M --drive-use-trash=false \
    2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "sync run OK"
else
  log "FAILED: rclone sync"
  notify "restic drive-sync FAILED (cellar)" "See journalctl -t $TAG or /var/log/${TAG}.log"
  exit 1
fi
