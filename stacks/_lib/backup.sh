#!/usr/bin/env bash
#
# backup.sh: a node's backups, built from each app's <app>/backup file. Every
# node's ./backup.sh calls this with its own directory.
#
#   ./backup.sh plan              what would be dumped and backed up; no root,
#                                 no network, changes nothing
#   sudo ./backup.sh doctor       checks everything the nightly run needs
#   sudo ./backup.sh keys         this node's SSH key, roastery's and cellar's
#                                 host keys, and the lines to authorize it
#   sudo ./backup.sh nightly      dump, push, files: what the timer runs
#   sudo ./backup.sh dump         databases → DUMP_DIR/<node>/<app>/
#   sudo ./backup.sh push         DUMP_DIR/<node>/ → the dump store on cellar
#   sudo ./backup.sh files        app data and this node's settings → restic
#   sudo ./backup.sh store        the whole dump store → restic (store node only)
#   sudo ./backup.sh restic ...   restic itself, pointed at the repository
#
# Where things go (runbook, 2026-09-27): databases are dumped on their own
# node and the dumps are pushed to cellar, the dump store; file data goes
# straight from each node into the restic repository on roastery. cellar
# backs the dump store up into the same repository (`store`), wakes roastery
# first, and copies the repository to Google Drive afterwards
# (stacks/cellar/restic).
#
# <app>/backup, one directive per line, # for comments:
#
#   pg      <name> <container> <database> <user>
#           pg_dump in custom format, run inside the app's own Postgres
#           container (so the client always matches the server), then
#           read back with pg_restore --list before it replaces the last one
#   mongo   <name> <container> <user> <password>
#           mongodump --archive --gzip, authenticating against admin
#   sqlite  <name> <path>
#           a consistent .dump of a live SQLite file, gzipped. The path may
#           be a glob (one dump per match). Runs as the file's owner, so a
#           root sqlite3 never leaves a root-owned -shm the app can't open
#   path    <path>
#           files, backed up straight to the repository
#   exclude <pattern>
#           left out of this app's paths: a pattern with a / is a path like
#           the ones above, one without matches that name at any depth
#
#   Values may be $KEY, looked up like everything else (fleet.env, the
#   node's .env, .env.local, then the app's secrets.env.local).
#   Paths are relative to DATA_DIR, or MEDIA_DIR/... for the media tree.
#   A trailing `optional` makes a missing container or file a note instead
#   of a failure (a database the app only creates once it's been set up).
#
# Every node also backs up its own settings, whatever the apps say:
# /opt/purrbrews/.env, .env.local, every secrets.env.local and /etc/purrbrews
# (pinned host keys, cellar's rclone config). They are what rebuilding a
# node from this repo needs and nothing else has.
#
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=restic-env.sh
source "$LIB/restic-env.sh"

load_node "${1:?usage: backup.sh <node dir> <command> [args]}"
shift
COMMAND="${1:-}"
[[ $# -gt 0 ]] && shift

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

require_root() {
  [[ $EUID -eq 0 ]] || die "run with sudo: the backup reads every app's data and uses root's SSH key."
  [[ -f "$ENV_LOCAL" ]] || die ".env.local is missing; run ./setup-secrets.sh first."
}

# ── Settings ─────────────────────────────────────────────────────────────────

load_settings() {
  DATA_DIR="$(env_value DATA_DIR)";   DATA_DIR="${DATA_DIR:-/srv/data}"
  MEDIA_DIR="$(env_value MEDIA_DIR)"; MEDIA_DIR="${MEDIA_DIR:-/srv/media}"
  DUMP_DIR="$(env_value DUMP_DIR)";   DUMP_DIR="${DUMP_DIR:-/srv/dumps}"
  DUMP_STORE_HOST="$(env_value DUMP_STORE_HOST)"
  NODE_IP="$(env_value NODE_IP)"
  NODE_DUMPS="$DUMP_DIR/$NODE_NAME"
  IS_STORE=0
  [[ -n "$NODE_IP" && "$NODE_IP" == "$DUMP_STORE_HOST" ]] && IS_STORE=1
  return 0
}

check_path() {  # check_path <app> <path>: dies (in this shell) on a path backup.sh won't take
  [[ "$2" != /* ]] || die "$1/backup: '$2' is absolute; paths are relative to DATA_DIR or MEDIA_DIR/."
  [[ "/$2/" != */../* ]] || die "$1/backup: '$2' climbs out with ..; not allowed."
}

resolve_path() {  # resolve_path <app> <path>: absolute path (check_path it first)
  local app="$1" p="$2"
  if [[ "$p" == MEDIA_DIR/* ]]; then
    printf '%s/%s' "$MEDIA_DIR" "${p#MEDIA_DIR/}"
  else
    printf '%s/%s' "$DATA_DIR" "$p"
  fi
}

resolve_value() {  # resolve_value <app> <token>: $KEY looked up, anything else as is
  local app="$1" token="$2" value
  if [[ "$token" == \$* ]]; then
    value="$(env_value "${token#\$}" "$app")"
    if is_placeholder "$value"; then
      warn "$app/backup: ${token} has no value on this node."
      return 1
    fi
    printf '%s' "$value"
  else
    printf '%s' "$token"
  fi
}

# Parsed directives, one array entry per line: "<app>|<kind>|<optional>|<fields...>"
# (fields separated by \x1f so a value can hold spaces).
DIRECTIVES=()

parse_backup_files() {
  local app spec line kind optional fields
  local -a words
  DIRECTIVES=()
  for app in "${APPS[@]}"; do
    spec="$NODE_DIR/$app/backup"
    [[ -f "$spec" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      read -r -a words <<< "$line"
      [[ ${#words[@]} -gt 0 ]] || continue
      kind="${words[0]}"
      optional=0
      if [[ "${words[-1]}" == optional ]]; then
        optional=1
        unset 'words[-1]'
      fi
      case "$kind" in
        pg)      [[ ${#words[@]} -eq 5 ]] || die "$app/backup: pg needs <name> <container> <database> <user>: $line" ;;
        mongo)   [[ ${#words[@]} -eq 5 ]] || die "$app/backup: mongo needs <name> <container> <user> <password>: $line" ;;
        sqlite)  [[ ${#words[@]} -eq 3 ]] || die "$app/backup: sqlite needs <name> <path>: $line" ;;
        path|exclude) [[ ${#words[@]} -eq 2 ]] || die "$app/backup: $kind takes exactly one path: $line" ;;
        *) die "$app/backup: '$kind' isn't pg, mongo, sqlite, path or exclude." ;;
      esac
      if [[ "$kind" =~ ^(pg|mongo|sqlite)$ ]]; then
        [[ "${words[1]}" =~ ^[A-Za-z0-9._-]+$ ]] || die "$app/backup: dump name '${words[1]}' should be letters, digits, . _ -"
      fi
      # Paths are checked now, so a bad one stops the run before anything is dumped.
      case "$kind" in
        sqlite) check_path "$app" "${words[2]}" ;;
        path)   check_path "$app" "${words[1]}" ;;
        exclude) [[ "${words[1]}" != */* ]] || check_path "$app" "${words[1]}" ;;
      esac
      fields="$(IFS=$'\x1f'; printf '%s' "${words[*]:1}")"
      DIRECTIVES+=("$app|$kind|$optional|$fields")
    done < "$spec"
  done
}

each() {  # each <kind>: prints the matching directives, one per line
  local d
  for d in "${DIRECTIVES[@]}"; do
    [[ "$(cut -d'|' -f2 <<< "$d")" == "$1" ]] && printf '%s\n' "$d"
  done
  return 0
}

split_directive() {  # sets D_APP D_KIND D_OPTIONAL D_FIELDS[]
  IFS='|' read -r D_APP D_KIND D_OPTIONAL rest <<< "$1"
  IFS=$'\x1f' read -r -a D_FIELDS <<< "$rest"
}

settings_paths() {  # the node's own settings, always backed up
  local f
  for f in "$ROOT/.env" "$ENV_LOCAL" "$NODE_DIR"/*/secrets.env.local "$BACKUP_ETC"; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}

# ── plan ─────────────────────────────────────────────────────────────────────

cmd_plan() {
  local d name
  load_settings
  parse_backup_files
  echo "$NODE_NAME: DATA_DIR=$DATA_DIR  dumps → $NODE_DUMPS"
  if [[ $IS_STORE -eq 1 ]]; then
    echo "  this node is the dump store: dumps stay here, and 'store' backs up $DUMP_DIR"
  else
    echo "  dumps pushed to ${DUMP_STORE_HOST:-?}:$DUMP_DIR/$NODE_NAME"
  fi
  echo
  echo "Dumps:"
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    name="${D_FIELDS[0]}"
    case "$D_KIND" in
      pg)     echo "  $D_APP/$name.pgdump  pg_dump ${D_FIELDS[2]} as ${D_FIELDS[3]} in ${D_FIELDS[1]}" ;;
      mongo)  echo "  $D_APP/$name.mongo.gz  mongodump in ${D_FIELDS[1]} as ${D_FIELDS[2]}" ;;
      sqlite) echo "  $D_APP/$name.sql.gz  sqlite .dump of $(resolve_path "$D_APP" "${D_FIELDS[1]}")" ;;
    esac
    [[ "$D_OPTIONAL" -eq 0 ]] || echo "      (optional)"
  done < <(each pg; each mongo; each sqlite)
  echo
  echo "Files (restic --host $NODE_NAME --tag files):"
  settings_paths | sed 's/^/  /'
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    echo "  $(resolve_path "$D_APP" "${D_FIELDS[0]}")$([[ "$D_OPTIONAL" -eq 1 ]] && echo '  (optional)')"
  done < <(each path)
  local excludes
  excludes="$(exclude_patterns)"
  if [[ -n "$excludes" ]]; then
    echo "Excluded:"
    sed 's/^/  /' <<< "$excludes"
  fi
}

# ── dump ─────────────────────────────────────────────────────────────────────

container_running() {
  [[ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]
}

publish() {  # publish <tmp> <final>: atomically replace the last good dump
  chmod 600 "$1"
  mv -f "$1" "$2"
  DUMPED+=("$2")
  note "$(basename "$(dirname "$2")")/$(basename "$2")  $(du -h "$2" | cut -f1)"
}

dump_pg() {  # dump_pg <app> <optional> <name> <container> <db> <user>
  local app="$1" optional="$2" name="$3" container db user out tmp
  container="$(resolve_value "$app" "$4")" || return 1
  db="$(resolve_value "$app" "$5")" || return 1
  user="$(resolve_value "$app" "$6")" || return 1
  out="$NODE_DUMPS/$app/$name.pgdump"; tmp="$out.partial"
  if ! container_running "$container"; then
    [[ "$optional" -eq 1 ]] && { note "$app/$name: $container isn't running; optional, skipped"; return 0; }
    warn "$app/$name: $container isn't running"; return 1
  fi
  # Local socket inside the container: the official images trust it, so no
  # password crosses the command line.
  if ! "${DOCKER[@]}" exec "$container" pg_dump -U "$user" -d "$db" -Fc > "$tmp"; then
    rm -f "$tmp"; warn "$app/$name: pg_dump failed"; return 1
  fi
  if ! "${DOCKER[@]}" exec -i "$container" pg_restore --list < "$tmp" > /dev/null; then
    rm -f "$tmp"; warn "$app/$name: the dump doesn't read back (pg_restore --list)"; return 1
  fi
  publish "$tmp" "$out"
}

dump_mongo() {  # dump_mongo <app> <optional> <name> <container> <user> <password>
  local app="$1" optional="$2" name="$3" container user password out tmp
  container="$(resolve_value "$app" "$4")" || return 1
  user="$(resolve_value "$app" "$5")" || return 1
  password="$(resolve_value "$app" "$6")" || return 1
  out="$NODE_DUMPS/$app/$name.mongo.gz"; tmp="$out.partial"
  if ! container_running "$container"; then
    [[ "$optional" -eq 1 ]] && { note "$app/$name: $container isn't running; optional, skipped"; return 0; }
    warn "$app/$name: $container isn't running"; return 1
  fi
  # The password goes in on stdin and becomes an argument only inside the
  # container, so it never shows in the host's process list or the journal.
  # shellcheck disable=SC2016  # $1 and $p expand inside the container's shell
  if ! printf '%s\n' "$password" | "${DOCKER[@]}" exec -i "$container" sh -c \
      'read -r p; exec mongodump --quiet --archive --gzip --authenticationDatabase admin --username "$1" --password "$p"' \
      sh "$user" > "$tmp"; then
    rm -f "$tmp"; warn "$app/$name: mongodump failed"; return 1
  fi
  if ! gzip -t "$tmp" 2>/dev/null || [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"; warn "$app/$name: the archive is empty or corrupt"; return 1
  fi
  publish "$tmp" "$out"
}

dump_sqlite() {  # dump_sqlite <app> <optional> <name> <path glob>
  local app="$1" optional="$2" name="$3" pattern files file suffix out tmp owner status=0
  pattern="$(resolve_path "$app" "$4")"
  command -v sqlite3 >/dev/null || { warn "sqlite3 isn't installed (apt install sqlite3)"; return 1; }
  shopt -s nullglob
  # shellcheck disable=SC2206  # the glob expansion is the point
  files=($pattern)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    [[ "$optional" -eq 1 ]] && { note "$app/$name: nothing at ${pattern}; optional, skipped"; return 0; }
    warn "$app/$name: nothing at $pattern"; return 1
  fi
  for file in "${files[@]}"; do
    suffix=''
    if [[ ${#files[@]} -gt 1 ]]; then
      suffix="${file#"$DATA_DIR"/}"; suffix="-${suffix//[^A-Za-z0-9._-]/_}"
    fi
    out="$NODE_DUMPS/$app/$name$suffix.sql.gz"; tmp="$out.partial"
    owner="$(stat -c '%u:%g' "$file")"
    # .dump inside one read transaction is consistent even while the app
    # writes; -readonly as the owner means this can't change the file or
    # leave root-owned WAL/SHM files behind.
    if ! setpriv --reuid="${owner%:*}" --regid="${owner#*:}" --clear-groups \
         sqlite3 -readonly -bail "$file" .dump | gzip -6 > "$tmp"; then
      rm -f "$tmp"; warn "$app/$name: sqlite3 .dump of $file failed"; status=1; continue
    fi
    # A complete dump ends by committing its transaction.
    if [[ "$(gzip -dc "$tmp" | tail -n1)" != "COMMIT;" ]]; then
      rm -f "$tmp"; warn "$app/$name: the dump of $file is incomplete"; status=1; continue
    fi
    publish "$tmp" "$out"
  done
  return $status
}

cmd_dump() {
  local d status=0 app dir f keep
  local -A apps_ok=()
  DUMPED=()
  load_settings
  parse_backup_files
  use_docker
  install -d -m 700 "$NODE_DUMPS"
  log "Dumping databases on $NODE_NAME → $NODE_DUMPS"
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    install -d -m 700 "$NODE_DUMPS/$D_APP"
    [[ -n "${apps_ok[$D_APP]:-}" ]] || apps_ok[$D_APP]=1
    if ! "dump_$D_KIND" "$D_APP" "$D_OPTIONAL" "${D_FIELDS[@]}"; then
      apps_ok[$D_APP]=0
      status=1
    fi
  done < <(each pg; each mongo; each sqlite)

  # A dump that isn't in any backup file any more would otherwise sit in the
  # store forever looking current. Only tidied for apps whose run fully
  # worked, so a failing dump never costs the last good one.
  for app in "${!apps_ok[@]}"; do
    [[ "${apps_ok[$app]}" -eq 1 ]] || continue
    dir="$NODE_DUMPS/$app"
    for f in "$dir"/*; do
      [[ -e "$f" ]] || continue
      keep=0
      for d in "${DUMPED[@]}"; do [[ "$d" == "$f" ]] && keep=1; done
      [[ $keep -eq 1 ]] || { rm -f "$f"; note "removed stale $app/$(basename "$f")"; }
    done
  done
  [[ ${#apps_ok[@]} -gt 0 ]] || note "no app on $NODE_NAME has a database to dump"
  return $status
}

# ── push ─────────────────────────────────────────────────────────────────────

cmd_push() {
  load_settings
  if [[ $IS_STORE -eq 1 ]]; then
    note "$NODE_NAME is the dump store; its dumps are already in place."
    return 0
  fi
  [[ -n "$DUMP_STORE_HOST" ]] || die "DUMP_STORE_HOST isn't set (stacks/fleet.env)."
  [[ -d "$NODE_DUMPS" ]] || die "no dumps at $NODE_DUMPS; run 'dump' first."
  command -v rsync >/dev/null || die "rsync isn't installed (apt install rsync)."
  backup_ssh_opts
  log "Pushing $NODE_DUMPS → dumps@$DUMP_STORE_HOST"
  # cellar pins this key to `rrsync -wo <DUMP_DIR>/<node>`, so the far side
  # of the path is already this node's folder there and nothing else.
  # --delay-updates: the store never holds half of tonight's set.
  rsync -rt --delete --delay-updates --partial-dir=.rsync-partial \
    --exclude='*.partial' \
    -e "ssh ${BACKUP_SSH_OPTS[*]}" \
    "$NODE_DUMPS/" "dumps@$DUMP_STORE_HOST:./"
}

# ── files / store ────────────────────────────────────────────────────────────

exclude_patterns() {  # every app's excludes, made absolute under that app's paths
  local d p app pattern
  local -A roots=()
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    roots[$D_APP]+="$(resolve_path "$D_APP" "${D_FIELDS[0]}")"$'\n'
  done < <(each path)
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    app="$D_APP"; pattern="${D_FIELDS[0]}"
    if [[ "$pattern" == */* ]]; then
      resolve_path "$app" "$pattern"; echo
    else
      [[ -n "${roots[$app]:-}" ]] || die "$app/backup: exclude '$pattern' but the app has no path to exclude it from."
      while IFS= read -r p; do
        [[ -n "$p" ]] && printf '%s/**/%s\n' "$p" "$pattern"
      done <<< "${roots[$app]}"
    fi
  done < <(each exclude)
  return 0
}

run_restic_backup() {  # run_restic_backup <tag> <paths...>
  local tag="$1" rc=0; shift
  local -a args=(backup --host "$NODE_NAME" --tag nightly --tag "$tag" --exclude-caches --no-scan)
  local pattern
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && args+=(--exclude "$pattern")
  done < <(exclude_patterns)
  restic_env
  mkdir -p "$BACKUP_CACHE"
  if ! reach_repo; then
    warn "roastery ($REPO_HOST) didn't answer on port 22 within ${BACKUP_WAIT_SECONDS}s; is it awake?"
    return 1
  fi
  "${RESTIC[@]}" "${args[@]}" "$@" || rc=$?
  # 3: the snapshot was saved but some files couldn't be read. Worth an
  # alert, not worth pretending nothing was saved.
  if [[ $rc -eq 3 ]]; then
    warn "restic saved the snapshot but couldn't read some files (see above)"
  fi
  return $rc
}

cmd_files() {
  local d path status=0
  local -a paths=()
  load_settings
  parse_backup_files
  mapfile -t paths < <(settings_paths)
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    path="$(resolve_path "$D_APP" "${D_FIELDS[0]}")"
    if [[ -e "$path" ]]; then
      paths+=("$path")
    elif [[ "$D_OPTIONAL" -eq 1 ]]; then
      note "$D_APP: $path doesn't exist; optional, skipped"
    else
      warn "$D_APP: $path doesn't exist"
      status=1
    fi
  done < <(each path)
  log "Backing up $NODE_NAME's files (${#paths[@]} paths) → roastery"
  run_restic_backup files "${paths[@]}" || status=1
  return $status
}

cmd_store() {
  load_settings
  [[ $IS_STORE -eq 1 ]] || die "'store' only runs on the dump store ($DUMP_STORE_HOST), not $NODE_NAME."
  [[ -d "$DUMP_DIR" ]] || die "no dump store at $DUMP_DIR."
  log "Backing up the dump store $DUMP_DIR → roastery"
  # --host is the store node; the per-node folders inside keep them apart.
  # No app excludes apply: DIRECTIVES stays empty.
  DIRECTIVES=()
  run_restic_backup dumps "$DUMP_DIR"
}

# ── nightly ──────────────────────────────────────────────────────────────────

cmd_nightly() {
  local failed=()
  # Anything that ends this run early (a typo in a backup file, a missing
  # setting) still has to reach ntfy, or a broken night looks like a quiet one.
  trap 'rc=$?; [[ $rc -eq 0 || -n "${NIGHTLY_NOTIFIED:-}" ]] || notify "backup FAILED on $NODE_NAME" "Stopped early (exit $rc). journalctl -u purrbrews-backup@$NODE_NAME"' EXIT
  cmd_dump || failed+=(dump)
  # Push even after a failed dump: the others still went through, and the
  # store keeps last night's copy of the one that didn't.
  cmd_push || failed+=(push)
  cmd_files || failed+=(files)
  if [[ ${#failed[@]} -gt 0 ]]; then
    NIGHTLY_NOTIFIED=1
    notify "backup FAILED on $NODE_NAME" "Failed: ${failed[*]}. journalctl -u purrbrews-backup@$NODE_NAME"
    die "nightly backup: ${failed[*]} failed."
  fi
  log "nightly backup on $NODE_NAME OK"
}

# ── keys ─────────────────────────────────────────────────────────────────────

pin_host() {  # pin_host <label> <host>: add its ed25519 key to BACKUP_KNOWN_HOSTS once
  local label="$1" host="$2" scanned
  if ssh-keygen -F "$host" -f "$BACKUP_KNOWN_HOSTS" >/dev/null 2>&1; then
    note "$label ($host): already pinned"
    return 0
  fi
  scanned="$(ssh-keyscan -T 5 -t ed25519 "$host" 2>/dev/null)" || true
  if [[ -z "$scanned" ]]; then
    warn "$label ($host) didn't answer ssh-keyscan; is it on and is its SSH server running? Run 'keys' again later."
    return 1
  fi
  printf '%s\n' "$scanned" >> "$BACKUP_KNOWN_HOSTS"
  chmod 644 "$BACKUP_KNOWN_HOSTS"
  note "$label ($host) pinned:"
  ssh-keygen -lf <(printf '%s\n' "$scanned") | sed 's/^/      /'
  note "compare that with the fingerprint on $label itself before trusting it."
}

cmd_keys() {
  local pub status=0
  load_settings
  install -d -m 700 /root/.ssh
  install -d -m 755 "$BACKUP_ETC"
  if [[ ! -f "$BACKUP_KEY" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "purrbrews-backup@$NODE_NAME" -f "$BACKUP_KEY"
    note "made $BACKUP_KEY"
  else
    note "$BACKUP_KEY already exists"
  fi
  pub="$(cat "$BACKUP_KEY.pub")"

  log "Host keys"
  pin_host roastery "$(env_value ROASTERY_LAN_IP)" || status=1
  [[ $IS_STORE -eq 1 ]] || pin_host "dump store" "$DUMP_STORE_HOST" || status=1

  log "Authorize this node"
  echo "On roastery, one line in stacks/roastery/backup-target/authorized_keys, then"
  echo "run setup.ps1 again (it copies the file to where sshd reads it):"
  echo
  echo "from=\"$NODE_IP\",restrict $pub"
  echo
  if [[ $IS_STORE -eq 0 ]]; then
    echo "On cellar, one line in stacks/cellar/restic/dump-store.keys, then"
    echo "sudo ./restic/dump-store-setup.sh there:"
    echo
    echo "$NODE_NAME from=\"$NODE_IP\" $pub"
    echo
  fi
  return $status
}

# ── doctor ───────────────────────────────────────────────────────────────────

cmd_doctor() {
  local bad=0 d c
  ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
  fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; bad=1; }
  load_settings
  parse_backup_files
  use_docker

  log "Tools"
  for c in restic rsync sqlite3 setpriv ssh gzip flock curl; do
    if command -v "$c" >/dev/null; then ok "$c"; else fail "$c isn't installed"; fi
  done

  log "Settings"
  if (restic_env) 2>/dev/null; then ok "repository and password set"; else fail "$( (restic_env) 2>&1 | tail -n1)"; fi
  [[ -f "$BACKUP_KEY" ]] && ok "SSH key $BACKUP_KEY" || fail "no SSH key; run 'keys'"
  if [[ -f "$BACKUP_KNOWN_HOSTS" ]] && ssh-keygen -F "$(env_value ROASTERY_LAN_IP)" -f "$BACKUP_KNOWN_HOSTS" >/dev/null; then
    ok "roastery's host key pinned"
  else
    fail "roastery's host key isn't pinned; run 'keys'"
  fi
  if [[ $IS_STORE -eq 0 ]]; then
    if [[ -f "$BACKUP_KNOWN_HOSTS" ]] && ssh-keygen -F "$DUMP_STORE_HOST" -f "$BACKUP_KNOWN_HOSTS" >/dev/null; then
      ok "the dump store's host key pinned"
    else
      fail "the dump store's host key isn't pinned; run 'keys'"
    fi
  fi

  log "What the apps ask for"
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    split_directive "$d"
    case "$D_KIND" in
      pg|mongo)
        c="$(resolve_value "$D_APP" "${D_FIELDS[1]}" 2>/dev/null)" || c=''
        if [[ -n "$c" ]] && container_running "$c"; then ok "$D_APP/${D_FIELDS[0]}: $c running"
        elif [[ "$D_OPTIONAL" -eq 1 ]]; then ok "$D_APP/${D_FIELDS[0]}: $c not running (optional)"
        else fail "$D_APP/${D_FIELDS[0]}: $c isn't running"; fi ;;
      sqlite|path)
        c="$(resolve_path "$D_APP" "${D_FIELDS[-1]}")"
        if compgen -G "$c" >/dev/null; then ok "$D_APP: $c"
        elif [[ "$D_OPTIONAL" -eq 1 ]]; then ok "$D_APP: $c missing (optional)"
        else fail "$D_APP: $c doesn't exist"; fi ;;
    esac
  done < <(each pg; each mongo; each sqlite; each path)

  log "Reaching the far ends"
  if (restic_env && { [[ -z "$REPO_HOST" ]] || port_open "$REPO_HOST" 22; }); then
    if (restic_env && "${RESTIC[@]}" cat config >/dev/null 2>&1); then
      ok "repository opens (restic cat config)"
    else
      fail "roastery answers but the repository doesn't open: key not authorized, wrong password, or not initialised"
    fi
  else
    fail "roastery isn't answering on port 22 (asleep? wake it and run doctor again)"
  fi
  if [[ $IS_STORE -eq 0 ]]; then
    backup_ssh_opts
    # The store only lets a node write (rrsync -wo), so this is a dry-run
    # upload of an empty folder: it proves the key and the path, sends nothing.
    local empty
    empty="$(mktemp -d)"
    if [[ -f "$BACKUP_KEY" ]] && rsync -n -r -e "ssh ${BACKUP_SSH_OPTS[*]}" "$empty/" "dumps@$DUMP_STORE_HOST:./" >/dev/null 2>&1; then
      ok "the dump store accepts this node's key"
    else
      fail "the dump store doesn't accept this node's key yet (dump-store-setup.sh on cellar)"
    fi
    rmdir "$empty"
  fi

  echo
  [[ $bad -eq 0 ]] && echo "All good." || { echo "Fix the FAILs above; nothing was changed."; return 1; }
}

# ── dispatch ─────────────────────────────────────────────────────────────────

case "$COMMAND" in
  plan)    cmd_plan ;;
  doctor)  require_root; cmd_doctor ;;
  keys)    require_root; cmd_keys ;;
  dump)    require_root; with_lock cmd_dump ;;
  push)    require_root; with_lock cmd_push ;;
  files)   require_root; with_lock cmd_files ;;
  store)   require_root; with_lock cmd_store ;;
  nightly) require_root; with_lock cmd_nightly ;;
  restic)  require_root; restic_env; exec "${RESTIC[@]}" "$@" ;;
  -h|--help|help) usage 0 ;;
  *) usage ;;
esac
