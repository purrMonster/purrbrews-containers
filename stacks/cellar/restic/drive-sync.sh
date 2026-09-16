#!/usr/bin/env bash
#
# drive-sync.sh — step four of infrastructure.md §7's chain: syncs the
# restic repository to encrypted Google Drive (5 TB, owned) via rclone.
#
# Per §7's own gotchas:
#   - Uses rclone's crypt remote wrapping a Drive remote (repository is
#     already restic-encrypted; the crypt layer additionally hides
#     filenames/structure from Google itself -- belt and suspenders, not
#     redundant: restic's encryption protects contents, crypt protects
#     metadata).
#   - Own Google API client ID (RCLONE_DRIVE_CLIENT_ID/_SECRET in
#     restic/secrets.env.local) -- rclone's shared default is documented
#     as the single biggest cause of 403 userRateLimitExceeded.
#   - --tpslimit=10 --drive-chunk-size=256M --drive-use-trash=false, and a
#     larger restic pack size (set via RESTIC_PACK_SIZE at backup time, not
#     here) so fewer, larger objects get shipped -- Drive throttles a
#     restic repo hard because it's normally thousands of small pack files.
#
# rclone.conf is generated from rclone.conf.template by render-configs.sh
# (uses the client ID/secret above) but the OAuth token itself still needs
# one interactive `rclone config reconnect drive-crypt:` run, by hand, the
# first time -- not scriptable, needs a browser.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$DIR")"
TAG="cellar-restic-drive-sync"

log() { logger -t "$TAG" "$*"; echo "$*"; }
notify() {
  [[ -n "${NTFY_URL:-}" ]] && curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

[[ -f "${STACK_DIR}/.env.local" ]] || { log "FAILED: no .env.local"; exit 1; }
set -a
source "${STACK_DIR}/.env.local"
set +a

command -v rclone >/dev/null 2>&1 || { log "FAILED: rclone not installed"; exit 1; }
[[ -f "${DIR}/rclone.conf" ]] || { log "FAILED: rclone.conf not rendered -- run ../render-configs.sh, then 'rclone config reconnect drive-crypt: --config ${DIR}/rclone.conf'"; exit 1; }

REPO="${CELLAR_HDD_MOUNT}/restic-repo"

log "sync run starting"
if rclone sync "$REPO" drive-crypt: \
    --config "${DIR}/rclone.conf" \
    --tpslimit=10 --drive-chunk-size=256M --drive-use-trash=false \
    2>&1 | tee -a "/var/log/${TAG}.log"; then
  log "sync run OK"
else
  log "FAILED: rclone sync"
  notify "restic drive-sync FAILED (cellar)" "See journalctl -t ${TAG} or /var/log/${TAG}.log"
  exit 1
fi

echo
echo "Reminder (infrastructure.md §7): a single Google account is its own"
echo "point of failure. Keep the small critical set (Vaultwarden export,"
echo "Paperless documents, every node's .env.local -- ~20 GB) somewhere"
echo "else too, not just here."
