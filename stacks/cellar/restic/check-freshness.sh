#!/usr/bin/env bash
#
# check-freshness.sh: the morning check (purrbrews-backup-check.timer,
# 06:00). A failed job alerts on its own; this catches the jobs that never
# ran at all: a dead timer, a node that was off, a roastery that slept
# through the night. Each of these must be younger than MAX_AGE_HOURS:
#
#   - every node's latest `files` snapshot    (a node with a <app>/backup file)
#   - the dump store's latest `dumps` snapshot
#   - the newest dump each node pushed here   (a node with pg/mongo/sqlite lines)
#   - the last good Drive sync
#
# The list of nodes comes from the repo (whoever has backup files), so a new
# node is checked the day its first backup file lands, and nobody has to
# remember to add it here.
#
#   sudo ./restic/check-freshness.sh           alerts on anything stale
#   sudo ./restic/check-freshness.sh --quiet   only the exit code and the alert
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: the repository is reached with root's backup key."
MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"
QUIET=0
[[ "${1:-}" == --quiet ]] && QUIET=1
DUMP_DIR="$(env_value DUMP_DIR)"; DUMP_DIR="${DUMP_DIR:-/srv/dumps}"
STATE=/var/lib/purrbrews

say() { [[ $QUIET -eq 1 ]] || echo "$@"; }

# Which nodes back up files, and which also dump databases.
file_nodes=(); dump_nodes=()
for conf in "$STACKS"/*/node.conf; do
  node="$(basename "$(dirname "$conf")")"
  compgen -G "$STACKS/$node/*/backup" >/dev/null || continue
  file_nodes+=("$node")
  if grep -qsE '^[[:space:]]*(pg|mongo|sqlite)[[:space:]]' "$STACKS/$node"/*/backup; then
    dump_nodes+=("$node")
  fi
done

stale=()
now="$(date +%s)"
limit=$(( MAX_AGE_HOURS * 3600 ))
age_h() { echo $(( ($1) / 3600 )); }

# ── snapshots ────────────────────────────────────────────────────────────────
restic_env
if ! wake_roastery 300; then
  stale+=("roastery unreachable: couldn't check any snapshot")
else
  json="$("${RESTIC[@]}" --retry-lock 30m snapshots --json --latest 1 --group-by host,tags)" \
    || { stale+=("restic snapshots failed"); json='[]'; }
  # host<TAB>tag<TAB>epoch for the newest snapshot per host and tag.
  latest="$(python3 -c '
import datetime, json, re, sys
for group in json.load(sys.stdin) or []:
    for snap in group.get("snapshots") or []:
        # restic writes nanoseconds, which fromisoformat may not take: drop the fraction.
        stamp = re.sub(r"\.\d+", "", snap["time"]).replace("Z", "+00:00")
        when = int(datetime.datetime.fromisoformat(stamp).timestamp())
        for tag in snap.get("tags") or []:
            print(snap["hostname"], tag, when, sep="\t")
' <<< "$json" 2>/dev/null)" || latest=''
  check_snapshot() {  # check_snapshot <host> <tag>
    local when
    when="$(awk -F'\t' -v h="$1" -v t="$2" '$1 == h && $2 == t { print $3 }' <<< "$latest" | sort -n | tail -n1)"
    if [[ -z "$when" ]]; then
      stale+=("$1: no '$2' snapshot at all")
    elif (( now - when > limit )); then
      stale+=("$1: last '$2' snapshot $(age_h $((now - when)))h ago")
    else
      say "ok  $1 $2 ($(age_h $((now - when)))h)"
    fi
  }
  for node in "${file_nodes[@]}"; do check_snapshot "$node" files; done
  check_snapshot "$NODE_NAME" dumps
fi

# ── dumps in the store ───────────────────────────────────────────────────────
for node in "${dump_nodes[@]}"; do
  newest="$(find "$DUMP_DIR/$node" -type f ! -name '*.partial' -printf '%T@\n' 2>/dev/null | sort -n | tail -n1)" || newest=''
  if [[ -z "$newest" ]]; then
    stale+=("$node: no dumps in $DUMP_DIR/$node")
  elif (( now - ${newest%.*} > limit )); then
    stale+=("$node: newest dump $(age_h $((now - ${newest%.*})))h old")
  else
    say "ok  $node dumps ($(age_h $((now - ${newest%.*})))h)"
  fi
done

# ── Drive ────────────────────────────────────────────────────────────────────
if [[ -f "$STATE/drive-sync.ok" ]]; then
  synced="$(stat -c %Y "$STATE/drive-sync.ok")"
  if (( now - synced > limit )); then
    stale+=("Drive: last good sync $(age_h $((now - synced)))h ago")
  else
    say "ok  Drive ($(age_h $((now - synced)))h)"
  fi
else
  stale+=("Drive: never synced")
fi

if [[ ${#stale[@]} -gt 0 ]]; then
  printf 'STALE %s\n' "${stale[@]}"
  notify "backup: ${#stale[@]} thing(s) stale" "$(printf '%s\n' "${stale[@]}")"
  exit 1
fi
say "Everything backed up within ${MAX_AGE_HOURS}h."
