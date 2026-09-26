#!/usr/bin/env bash
#
# restic-init.sh: create the restic repository on cellar's HDD. Once, by
# hand, before the backup timer is enabled. restic-backup.sh deliberately
# won't create it: backing up into a repository that silently wasn't there
# is the exact failure the old rsync mirror had for weeks.
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
[[ -f "$ENV_LOCAL" ]] || die "no .env.local; run ../setup-secrets.sh first."
[[ -f "$DIR/secrets.env.local" ]] || die "no restic/secrets.env.local; run ../setup-secrets.sh first."
export_env restic
command -v restic >/dev/null || die "restic isn't installed (apt install restic)."

REPO="${CELLAR_HDD_MOUNT:?}/restic-repo"
export RESTIC_PASSWORD

if restic -r "$REPO" snapshots >/dev/null 2>&1; then
  echo "Repository already exists at $REPO; nothing to do."
  exit 0
fi
echo "Creating the restic repository at $REPO"
mkdir -p "$REPO"
restic -r "$REPO" init
echo "Done. RESTIC_PASSWORD is in restic/secrets.env.local; make sure flask has a copy."
