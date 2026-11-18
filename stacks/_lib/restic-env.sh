# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables set here are used by the scripts that source this
#
# restic-env.sh: sourced by backup.sh and cellar's restic/ scripts, never run
# on its own. Everything a node needs to talk to the backup repository and
# the dump store, both on cellar, in one place, so the two sides can't
# disagree about a key path or an ssh option.
#
# Needs common.sh and load_node first.

# The node's SSH identity for backups. root's, because the nightly job runs as
# root (it reads every app's data, whoever owns it). One key serves both the
# repository (SFTP, account `burmilla`) and the dump store (rrsync, account
# `dumps`); cellar limits what each account can do with it.
BACKUP_KEY="${BACKUP_KEY:-/root/.ssh/purrbrews-backup}"
# The hub's host keys: pinned by `backup.sh keys` when they
# answer, otherwise on the first connection (accept-new: a new host is
# trusted once, a changed key is refused). Kept apart from root's own
# known_hosts so a stray `ssh` never changes what backups trust.
BACKUP_ETC="${BACKUP_ETC:-/etc/purrbrews}"
BACKUP_KNOWN_HOSTS="$BACKUP_ETC/backup_known_hosts"
# restic's local cache: speeds up every run, safe to delete.
BACKUP_CACHE="${BACKUP_CACHE:-/var/cache/purrbrews-restic}"
# All four can be overridden from the environment; only the tests do.
# How long a node waits for the repository's SSH before giving up. cellar is
# always on, so this only matters when it is rebooting (an update, a power
# cut that brought everything back at once).
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-600}"
BACKUP_LOCK="${BACKUP_LOCK:-/run/lock/purrbrews-backup.lock}"

backup_ssh_opts() {
  BACKUP_SSH_OPTS=(-i "$BACKUP_KEY" -o IdentitiesOnly=yes -o BatchMode=yes
                   -o ConnectTimeout=10 -o ServerAliveInterval=30
                   -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$BACKUP_KNOWN_HOSTS")
}

# restic_env: exports RESTIC_REPOSITORY / RESTIC_PASSWORD / RESTIC_CACHE_DIR
# and sets RESTIC (the command to run, with the SFTP transport) plus
# REPO_USER_HOST, REPO_HOST and REPO_PATH for the scripts that need the parts.
# Every node, the hub included, goes through the SFTP account, so every file
# in the repository belongs to `restic` and any node can read what another
# wrote. Only rclone's Drive sync reads it by path (repo_local_path).
parse_repo() {  # sets REPO_USER_HOST REPO_USER REPO_HOST REPO_PATH from BACKUP_REPOSITORY
  local repo
  repo="$(env_value BACKUP_REPOSITORY)"
  is_placeholder "$repo" && die "BACKUP_REPOSITORY isn't set (stacks/fleet.env)."
  REPO_USER_HOST=''; REPO_HOST=''; REPO_PATH="$repo"
  if [[ "$repo" == sftp:* ]]; then
    [[ "$repo" =~ ^sftp:([^@:]+@)?([^:/]+):(/.*)$ ]] \
      || die "BACKUP_REPOSITORY must look like sftp:user@host:/path, not '$repo'."
    REPO_USER_HOST="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    REPO_USER="${BASH_REMATCH[1]%@}"; REPO_USER="${REPO_USER:-restic}"
    REPO_HOST="${BASH_REMATCH[2]}"
    REPO_PATH="${BASH_REMATCH[3]}"
  elif [[ "$repo" != /* ]]; then
    # A local path is allowed (the tests use one, and so would a restore from
    # a disk plugged straight into a node); other restic backends aren't.
    die "BACKUP_REPOSITORY must be sftp:user@host:/path or an absolute path, not '$repo'."
  fi
}

restic_env() {
  local repo password
  parse_repo
  repo="$(env_value BACKUP_REPOSITORY)"

  password="$(env_value RESTIC_PASSWORD restic)"
  is_placeholder "$password" \
    && die "RESTIC_PASSWORD isn't set; run ./setup-secrets.sh (it's in restic/secrets.conf)."

  export RESTIC_REPOSITORY="$repo"
  export RESTIC_PASSWORD="$password"
  export RESTIC_CACHE_DIR="$BACKUP_CACHE"
  backup_ssh_opts
  RESTIC=(restic)
  if [[ -n "$REPO_HOST" ]]; then
    # Through rclone's SFTP backend, which restic drives with `rclone serve
    # restic --stdio`, not restic's own. It was chosen when the repository was
    # on Windows, whose OpenSSH refused restic's chmods (runbook, 2026-09-27).
    # cellar's OpenSSH wouldn't, but this is the path the tests and the old
    # fleet's nights exercised, so it stays. The remote is defined here
    # in the environment: no rclone config to keep on every node.
    export RESTIC_REPOSITORY="rclone:pbrepo:$REPO_PATH"
    export RCLONE_CONFIG_PBREPO_TYPE=sftp
    export RCLONE_CONFIG_PBREPO_HOST="$REPO_HOST"
    export RCLONE_CONFIG_PBREPO_USER="$REPO_USER"
    export RCLONE_CONFIG_PBREPO_KEY_FILE="$BACKUP_KEY"
    export RCLONE_CONFIG_PBREPO_KNOWN_HOSTS_FILE="$BACKUP_KNOWN_HOSTS"
    export RCLONE_CONFIG_PBREPO_SHELL_TYPE=none
    export RCLONE_CONFIG_PBREPO_SET_MODTIME=false
    export RCLONE_CONFIG_PBREPO_DISABLE_HASHCHECK=true
  fi
}

# pin_repo_host: rclone checks the host key strictly against
# BACKUP_KNOWN_HOSTS and has no accept-new, so the first time the hub
# answers, its keys are added here (the same trust-on-first-use the ssh
# options give the dump store). All key types, not just ed25519: rclone may
# negotiate another, and a host listed with the wrong type is a "mismatch".
# A changed key is never replaced.
pin_repo_host() {
  [[ -n "$REPO_HOST" ]] || return 0
  [[ -w "$(dirname "$BACKUP_KNOWN_HOSTS")" ]] || return 0
  local scanned type key have added=0
  tidy_known_hosts
  # Only real key lines: some ssh-keyscan versions print their "# host:22
  # SSH-2.0-…" banners on stdout, and rclone's known_hosts parser rejects
  # the whole file over one such line (runbook, 2026-09-27).
  scanned="$(ssh-keyscan -T 5 "$REPO_HOST" 2>/dev/null | awk '$1 !~ /^#/ && $2 ~ /^(ssh-|ecdsa-)/ && $3 ~ /^[A-Za-z0-9+\/]+=*$/' | sort -u)" || true
  [[ -n "$scanned" ]] || return 1
  have="$(ssh-keygen -F "$REPO_HOST" -f "$BACKUP_KNOWN_HOSTS" 2>/dev/null | grep -v '^#' || true)"
  while read -r _ type key; do
    [[ -n "${key:-}" ]] || continue
    if grep -qF " $type $key" <<< "$have"; then
      continue
    elif grep -qF " $type " <<< "$have"; then
      warn "$REPO_HOST's $type host key has CHANGED since it was pinned; not trusting it. Check before editing $BACKUP_KNOWN_HOSTS."
      return 1
    fi
    printf '%s %s %s\n' "$REPO_HOST" "$type" "$key" >> "$BACKUP_KNOWN_HOSTS"
    added=$((added + 1))
  done <<< "$scanned"
  chmod 644 "$BACKUP_KNOWN_HOSTS" 2>/dev/null || true
  [[ $added -eq 0 ]] || echo "pinned $added host key(s) for $REPO_HOST"
}

# tidy_known_hosts: drop anything in BACKUP_KNOWN_HOSTS that isn't a key line
# (and exact duplicates). The first version of pin_repo_host wrote
# ssh-keyscan's banner lines into it on cellar.
tidy_known_hosts() {
  [[ -f "$BACKUP_KNOWN_HOSTS" && -w "$BACKUP_KNOWN_HOSTS" ]] || return 0
  local tmp
  tmp="$(mktemp "$BACKUP_KNOWN_HOSTS.XXXXXX")"
  awk '/^#/ || ($2 ~ /^(ssh-|ecdsa-|sk-)/ && $3 ~ /^[A-Za-z0-9+\/]+=*$/) { if (!seen[$0]++) print }' \
    "$BACKUP_KNOWN_HOSTS" > "$tmp"
  if cmp -s "$tmp" "$BACKUP_KNOWN_HOSTS"; then
    rm -f "$tmp"
  else
    chmod 644 "$tmp"
    mv -f "$tmp" "$BACKUP_KNOWN_HOSTS"
    echo "tidied $BACKUP_KNOWN_HOSTS (removed lines that weren't host keys)"
  fi
}

port_open() {  # port_open <host> <port>: true if something accepts a TCP connection
  timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

wait_for_repo() {  # wait_for_repo [seconds]: the repository's SSH answering, or false
  local limit="${1:-$BACKUP_WAIT_SECONDS}" waited=0
  [[ -n "$REPO_HOST" ]] || return 0  # a local repository is always there
  until port_open "$REPO_HOST" 22; do
    (( waited >= limit )) && return 1
    sleep 10
    waited=$((waited + 10))
  done
  pin_repo_host
}

# notify <title> <message>: an ntfy alert, best effort. NTFY_URL is the topic
# URL (with ?auth=… if the topic needs it), from restic/secrets.conf. A dead
# ntfy must never turn a good backup into a failed one.
notify() {
  local url
  url="$(env_value NTFY_URL restic)"
  is_placeholder "$url" && return 0
  curl -fsS -m 10 -H "Title: $1" -H "Tags: floppy_disk" -d "$2" "$url" >/dev/null 2>&1 || true
}

# with_lock <command...>: one backup job at a time on a node. The timer and a
# hand-run `./backup.sh nightly` must not interleave dumps, and on cellar a
# slow store backup must finish before prune starts. Waits up to an hour.
with_lock() {
  exec 9>"$BACKUP_LOCK"
  flock -w "${BACKUP_LOCK_WAIT:-3600}" 9 \
    || die "another backup job has held $BACKUP_LOCK for an hour; not starting."
  "$@"
}

# reach_repo [seconds]: what every job calls before touching the repository.
# There used to be a wake-on-LAN here, for when the repository lived on a
# workstation that slept (retired 2026-11); cellar doesn't sleep.
reach_repo() {
  restic_env
  wait_for_repo "$@"
}

# repo_local_path: where the repository is on this machine's disk, for the
# one reader that goes by path (drive-sync.sh, through rclone). A local
# BACKUP_REPOSITORY is its own path; an SFTP one is only on disk on the hub,
# inside the account's chroot: BACKUP_REPO_ROOT + the path the nodes see.
repo_local_path() {
  parse_repo
  if [[ -z "$REPO_HOST" ]]; then
    printf '%s' "$REPO_PATH"
  elif [[ "$BACKUP_HUB" == true ]]; then
    local chroot
    chroot="$(env_value BACKUP_REPO_ROOT)"
    is_placeholder "$chroot" && die "BACKUP_REPO_ROOT isn't set (stacks/fleet.env)."
    printf '%s%s' "${chroot%/}" "$REPO_PATH"
  else
    die "the repository is only on disk on the backup hub, not on $NODE_NAME."
  fi
}
