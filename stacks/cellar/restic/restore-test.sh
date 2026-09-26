#!/usr/bin/env bash
#
# restore-test.sh: prove a backup comes back, not just that it was written.
# Restores into a scratch directory and checks what came out; touches
# nothing live.
#
#   sudo ./restic/restore-test.sh                      from roastery
#   sudo ./restic/restore-test.sh --from drive         from the Google Drive copy
#   sudo ./restic/restore-test.sh --host percolator    whose files to sample (default percolator)
#   sudo ./restic/restore-test.sh --files 50           how many files to sample (default 20)
#   sudo ./restic/restore-test.sh --keep               leave the scratch directory for a look
#
# What it does:
#   1. restores the latest `dumps` snapshot (every node's database dumps) and
#      reads each one back: pg_restore --list for Postgres, a load into an
#      in-memory SQLite for SQLite, gzip -t for Mongo;
#   2. restores a random sample of files from the chosen host's latest `files`
#      snapshot and checks each one's size against what the snapshot says.
#
# Worth running after any change to the backup setup, and every few months
# anyway, from Drive at least once: the offsite copy is the one that matters
# on the worst day.
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: the repository is reached with root's backup key."

FROM=roastery; HOST=percolator; SAMPLE=20; KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="${2:?}"; shift 2 ;;
    --host) HOST="${2:?}"; shift 2 ;;
    --files) SAMPLE="${2:?}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) die "unknown option $1 (see the top of this file)" ;;
  esac
done
[[ "$FROM" == roastery || "$FROM" == drive ]] || die "--from is roastery or drive"
[[ "$SAMPLE" =~ ^[0-9]+$ ]] || die "--files takes a number"
# The newest Postgres client reads every older dump format, so one image
# checks every node's dumps. Pinned like everything else.
PG_IMAGE=postgres:18

restic_env
if [[ "$FROM" == drive ]]; then
  command -v rclone >/dev/null || die "rclone isn't installed."
  [[ -f "$BACKUP_ETC/rclone.conf" ]] || die "no $BACKUP_ETC/rclone.conf; run drive-setup.sh first."
  # restic's rclone backend: restic starts `rclone serve restic --stdio`
  # itself, so nothing is downloaded that the checks don't ask for.
  export RCLONE_CONFIG="$BACKUP_ETC/rclone.conf"
  export RESTIC_REPOSITORY=rclone:drive-crypt:repo
  RESTIC=(restic)
else
  wake_roastery || die "roastery isn't answering."
fi

SCRATCH="$(mktemp -d /var/tmp/purrbrews-restore-test.XXXXXX)"
cleanup() { [[ $KEEP -eq 1 ]] && echo "Left in $SCRATCH" || rm -rf "$SCRATCH"; }
trap cleanup EXIT
failures=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
flunk() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }

# ── 1. database dumps ────────────────────────────────────────────────────────
log "Restoring the latest dumps snapshot ($FROM)"
"${RESTIC[@]}" restore latest --tag dumps --target "$SCRATCH/dumps" >/dev/null
use_docker
count=0
while IFS= read -r -d '' f; do
  count=$((count + 1))
  name="${f#"$SCRATCH/dumps"}"
  case "$f" in
    *.pgdump)
      if "${DOCKER[@]}" run --rm -i --entrypoint pg_restore "$PG_IMAGE" --list < "$f" >/dev/null 2>&1; then
        pass "$name ($(du -h "$f" | cut -f1), pg_restore reads it)"
      else
        flunk "$name: pg_restore can't read it"
      fi ;;
    *.sql.gz)
      # A full load, not just a gunzip: a dump that doesn't replay is useless.
      if gzip -dc "$f" | sqlite3 -bail ':memory:' >/dev/null 2>&1; then
        pass "$name (replays into SQLite)"
      else
        flunk "$name: doesn't replay into SQLite"
      fi ;;
    *.mongo.gz)
      if gzip -t "$f" 2>/dev/null && [[ -s "$f" ]]; then
        pass "$name (archive intact; a real mongorestore needs a Mongo to restore into)"
      else
        flunk "$name: corrupt archive"
      fi ;;
  esac
done < <(find "$SCRATCH/dumps" -type f \( -name '*.pgdump' -o -name '*.sql.gz' -o -name '*.mongo.gz' \) -print0)
[[ $count -gt 0 ]] || flunk "the dumps snapshot has no dumps in it"

# ── 2. a sample of files ─────────────────────────────────────────────────────
log "Restoring $SAMPLE random files from $HOST's latest files snapshot ($FROM)"
listing="$SCRATCH/listing.json"
"${RESTIC[@]}" ls latest --host "$HOST" --tag files --json > "$listing" \
  || { flunk "no files snapshot for $HOST"; SAMPLE=0; }
# path<TAB>size for regular files, then a random sample of them.
mapfile -t picks < <(python3 -c '
import json, random, sys
files = []
for line in open(sys.argv[1]):
    item = json.loads(line)
    if item.get("struct_type") == "node" and item.get("type") == "file":
        files.append((item["path"], item.get("size", 0)))
random.shuffle(files)
for path, size in files[:int(sys.argv[2])]:
    print(f"{size}\t{path}")
' "$listing" "$SAMPLE" 2>/dev/null)
[[ $SAMPLE -eq 0 || ${#picks[@]} -gt 0 ]] || flunk "$HOST's snapshot lists no files"
for pick in "${picks[@]}"; do
  size="${pick%%$'\t'*}"; path="${pick#*$'\t'}"
  if "${RESTIC[@]}" restore latest --host "$HOST" --tag files --target "$SCRATCH/files" --include "$path" >/dev/null 2>&1 \
     && [[ -f "$SCRATCH/files$path" ]] && [[ "$(stat -c %s "$SCRATCH/files$path")" -eq "$size" ]]; then
    pass "$path ($size bytes)"
  else
    flunk "$path: didn't come back at $size bytes"
  fi
done

echo
if [[ $failures -eq 0 ]]; then
  echo "Restore test passed ($FROM)."
else
  notify "backup: restore test FAILED ($FROM)" "$failures check(s) failed; run restic/restore-test.sh on cellar to see which."
  die "$failures check(s) failed."
fi
