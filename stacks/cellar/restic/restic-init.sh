#!/usr/bin/env bash
#
# restic-init.sh — one-time repository creation on cellar's HDD. Run this
# once, by hand, before the backup timer is ever enabled; restic-backup.sh
# deliberately does NOT auto-init (backing up into a repo that silently
# didn't exist yet, because init was skipped, is a worse failure than
# refusing to run).
#
# This replaces the pre-restructure cellar/backup-mirror/ entirely, not
# just its name. That mirror.sh was a plain append-only rsync copy with no
# retention and (per the 2026-09-13 fleet audit, Tier 0 #1) never actually
# ran mirror_source() at all — every source line was commented out, so it
# copied zero bytes, nightly, silently, the whole time it existed. restic
# gives this node real versioned, deduplicated, encrypted backups instead
# — see infrastructure.md §7 for the full chain this is step one of
# (percolator dumps DBs -> cellar's restic pulls them -> roastery mirrors
# -> Google Drive -> carafe quarterly).
#
# Usage: ./restic-init.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(dirname "$DIR")"

[[ -f "${STACK_DIR}/.env.local" ]] || { echo "No .env.local -- run ../setup-secrets.sh first." >&2; exit 1; }
[[ -f "${DIR}/secrets.env.local" ]] || { echo "No secrets.env.local -- run ../generate-secrets.sh first." >&2; exit 1; }
set -a
source "${STACK_DIR}/.env.local"
source "${DIR}/secrets.env.local"
set +a

command -v restic >/dev/null 2>&1 || { echo "restic not installed -- apt install restic (bookworm-backports/trixie has a current version) and re-run." >&2; exit 1; }

REPO="${CELLAR_HDD_MOUNT}/restic-repo"
export RESTIC_PASSWORD

if restic -r "$REPO" snapshots >/dev/null 2>&1; then
  echo "Repository already exists at ${REPO} -- nothing to do."
  exit 0
fi

echo "Initializing restic repository at ${REPO}"
mkdir -p "$REPO"
restic -r "$REPO" init
echo "Done. RESTIC_PASSWORD lives in restic/secrets.env.local — make sure it's"
echo "also on flask (infrastructure.md §8) before relying on this repository."
