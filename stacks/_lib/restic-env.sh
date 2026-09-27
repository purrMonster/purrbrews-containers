# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables set here are used by the scripts that source this
#
# restic-env.sh: sourced by backup.sh and cellar's restic/ scripts, never run
# on its own. Everything a node needs to talk to the backup repository on
# roastery and the dump store on cellar, in one place, so the two sides can't
# disagree about a key path or an ssh option.
#
# Needs common.sh and load_node first.

# The node's SSH identity for backups. root's, because the nightly job runs as
# root (it reads every app's data, whoever owns it). One key serves both
# roastery (SFTP) and cellar (the dump store); the far end limits what it can do.
BACKUP_KEY="${BACKUP_KEY:-/root/.ssh/purrbrews-backup}"
# Host keys for roastery and cellar: pinned by `backup.sh keys` when they
# answer, otherwise on the first connection (accept-new: a new host is
# trusted once, a changed key is refused). Kept apart from root's own
# known_hosts so a stray `ssh` never changes what backups trust.
BACKUP_ETC="${BACKUP_ETC:-/etc/purrbrews}"
BACKUP_KNOWN_HOSTS="$BACKUP_ETC/backup_known_hosts"
# restic's local cache: speeds up every run, safe to delete.
BACKUP_CACHE="${BACKUP_CACHE:-/var/cache/purrbrews-restic}"
# All four can be overridden from the environment; only the tests do.
# How long a node waits for roastery to wake before giving up. cellar sends
# the wake-on-LAN at 01:25; the nodes start at 01:30; roastery takes a minute
# or two out of S3.
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
restic_env() {
  local repo password
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

  password="$(env_value RESTIC_PASSWORD restic)"
  is_placeholder "$password" \
    && die "RESTIC_PASSWORD isn't set; run ./setup-secrets.sh (it's in restic/secrets.conf)."

  export RESTIC_REPOSITORY="$repo"
  export RESTIC_PASSWORD="$password"
  export RESTIC_CACHE_DIR="$BACKUP_CACHE"
  backup_ssh_opts
  RESTIC=(restic)
  if [[ -n "$REPO_HOST" ]]; then
    # Not restic's own SFTP backend: it chmods every file it writes, and
    # Windows' OpenSSH answers that with SSH_FX_BAD_MESSAGE, so `restic init`
    # never got past its first key (runbook, 2026-09-27). rclone's SFTP
    # backend doesn't chmod, and with set_modtime off it sends no SETSTAT at
    # all; restic drives it through `rclone serve restic --stdio`. Same
    # account, key, chroot and path; the remote is defined here in the
    # environment, so there's no rclone config to keep on every node.
    export RESTIC_REPOSITORY="rclone:pbroastery:$REPO_PATH"
    export RCLONE_CONFIG_PBROASTERY_TYPE=sftp
    export RCLONE_CONFIG_PBROASTERY_HOST="$REPO_HOST"
    export RCLONE_CONFIG_PBROASTERY_USER="$REPO_USER"
    export RCLONE_CONFIG_PBROASTERY_KEY_FILE="$BACKUP_KEY"
    export RCLONE_CONFIG_PBROASTERY_KNOWN_HOSTS_FILE="$BACKUP_KNOWN_HOSTS"
    export RCLONE_CONFIG_PBROASTERY_SHELL_TYPE=none
    export RCLONE_CONFIG_PBROASTERY_SET_MODTIME=false
    export RCLONE_CONFIG_PBROASTERY_DISABLE_HASHCHECK=true
  fi
}

# pin_repo_host: rclone checks the host key strictly against
# BACKUP_KNOWN_HOSTS and has no accept-new, so the first time roastery
# answers, its keys are added here (the same trust-on-first-use the ssh
# options give the dump store). All key types, not just ed25519: rclone may
# negotiate another, and a host listed with the wrong type is a "mismatch".
# A changed key is never replaced.
pin_repo_host() {
  [[ -n "$REPO_HOST" ]] || return 0
  [[ -w "$(dirname "$BACKUP_KNOWN_HOSTS")" ]] || return 0
  local scanned line type key have added=0
  scanned="$(ssh-keyscan -T 5 "$REPO_HOST" 2>/dev/null | sort)" || true
  [[ -n "$scanned" ]] || return 1
  have="$(ssh-keygen -F "$REPO_HOST" -f "$BACKUP_KNOWN_HOSTS" 2>/dev/null | grep -v '^#' || true)"
  while read -r _ type key; do
    [[ -n "${key:-}" ]] || continue
    if grep -qF " $type $key" <<< "$have"; then
      continue
    elif grep -q " $type " <<< "$have"; then
      warn "roastery's $type host key has CHANGED since it was pinned; not trusting it. Check before editing $BACKUP_KNOWN_HOSTS."
      return 1
    fi
    printf '%s %s %s\n' "$REPO_HOST" "$type" "$key" >> "$BACKUP_KNOWN_HOSTS"
    added=$((added + 1))
  done <<< "$scanned"
  chmod 644 "$BACKUP_KNOWN_HOSTS" 2>/dev/null || true
  [[ $added -eq 0 ]] || echo "pinned $added host key(s) for $REPO_HOST"
}

port_open() {  # port_open <host> <port>: true if something accepts a TCP connection
  timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

wait_for_repo() {  # wait_for_repo [seconds]: roastery's SSH answering, or false
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

# ── roastery's wake-up (cellar only; the other nodes just wait) ─────────────

# send_magic_packet <mac>: wake-on-LAN, broadcast on the LAN. python3 rather
# than the wakeonlan package: every node already has python3 for rendering.
send_magic_packet() {
  python3 - "$1" "$(env_value LAN_CIDR)" <<'PY'
import ipaddress, socket, sys
mac = sys.argv[1].replace(':', '').replace('-', '').lower()
if len(mac) != 12 or any(c not in '0123456789abcdef' for c in mac):
    sys.exit(f'not a MAC address: {sys.argv[1]}')
broadcast = str(ipaddress.ip_network(sys.argv[2] or '255.255.255.255/32', strict=False).broadcast_address)
packet = b'\xff' * 6 + bytes.fromhex(mac) * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    for port in (9, 7):
        s.sendto(packet, (broadcast, port))
PY
}

# wake_roastery [seconds]: wakes roastery if it's asleep and waits for its SSH.
# Harmless when it's already up. Every cellar job that needs the repository
# starts with this, rather than trusting that the 01:25 wake is still holding:
# a machine woken with nobody at it goes back to sleep on its own schedule.
wake_roastery() {
  local mac
  restic_env
  [[ -n "$REPO_HOST" ]] || return 0
  port_open "$REPO_HOST" 22 && { pin_repo_host; return 0; }
  mac="$(env_value ROASTERY_WOL_MAC)"
  is_placeholder "$mac" && { warn "ROASTERY_WOL_MAC isn't set in .env.local, so roastery can't be woken."; return 1; }
  echo "roastery is asleep; sending wake-on-LAN to its USB NIC"
  send_magic_packet "$mac" || return 1
  wait_for_repo "${1:-300}"
}

# reach_repo [seconds]: what every job calls before touching the repository.
# Wakes roastery on the node that has its MAC (cellar), just waits elsewhere.
reach_repo() {
  if is_placeholder "$(env_value ROASTERY_WOL_MAC)"; then
    wait_for_repo "$@"
  else
    wake_roastery "${1:-$BACKUP_WAIT_SECONDS}"
  fi
}
