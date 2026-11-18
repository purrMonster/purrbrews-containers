#!/usr/bin/env bash
#
# repo-setup.sh: make cellar the home of the restic repository. Safe to
# re-run; run it again whenever restic/backup.keys changes. Replaces the
# Windows backup target on roastery (deprecated/stacks/roastery/backup-target).
#
#   - an SFTP-only system account, named by BACKUP_REPOSITORY (sftp:<user>@...);
#   - BACKUP_REPO_ROOT (root's, 755) as its chroot, and the repository folder
#     inside it (the path in BACKUP_REPOSITORY), the only place it can write;
#   - an sshd drop-in: AllowUsers it, and for it ChrootDirectory and
#     ForceCommand internal-sftp, so a key gets a file transfer and nothing
#     else (no shell, no forwarding, no other folder);
#   - its authorized_keys, rebuilt from restic/backup.keys plus cellar's own
#     key, each pinned to that node's address with from="<ip>".
#
# Every node, cellar included, writes the repository through this account,
# so every file in it belongs to the account and any node can read what
# another wrote. Only drive-sync.sh reads it by path, as root.
#
# restic/backup.keys (gitignored; copy backup.keys.example) is the same file
# dump-store-setup.sh reads: one line per node, as `backup.sh keys` printed it.
#
#   sudo ./restic/repo-setup.sh           set up, or bring up to date
#   sudo ./restic/repo-setup.sh --check   check backup.keys and print the
#                                         authorized_keys it would write;
#                                         changes nothing
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$(this_node_dir)"
CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  '') ;;
  *) die "usage: repo-setup.sh [--check]" ;;
esac
[[ $EUID -eq 0 || $CHECK -eq 1 ]] || die "run with sudo: it makes an account and writes its authorized_keys."
[[ "$BACKUP_HUB" == true ]] || die "the repository lives on the backup hub (node.conf BACKUP_HUB=true), not $NODE_NAME."
KEYS="${BACKUP_KEYS_FILE:-$DIR/backup.keys}"

repo="$(env_value BACKUP_REPOSITORY)"
[[ "$repo" =~ ^sftp:([a-z_][a-z0-9_-]*)@([^:/]+):(/[A-Za-z0-9._/-]+)$ ]] \
  || die "BACKUP_REPOSITORY must be sftp:<user>@<host>:/<path> to set up an account for it, not '$repo'."
USER_NAME="${BASH_REMATCH[1]}"; REPO_HOST="${BASH_REMATCH[2]}"; REPO_PATH="${BASH_REMATCH[3]%/}"
NODE_IP="$(env_value NODE_IP)"
[[ "$REPO_HOST" == "$NODE_IP" ]] \
  || die "BACKUP_REPOSITORY points at $REPO_HOST, but this is $NODE_NAME ($NODE_IP)."
CHROOT="$(env_value BACKUP_REPO_ROOT)"; CHROOT="${CHROOT%/}"
[[ "$CHROOT" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "BACKUP_REPO_ROOT (stacks/fleet.env) must be an absolute path, not '$CHROOT'."
REPO_DIR="$CHROOT$REPO_PATH"
# Named after the account, so a renamed account can't inherit a home that
# another one owns (sshd ignores keys in a home that isn't the user's).
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6 || true)"
HOME_DIR="${HOME_DIR:-/var/lib/$USER_NAME}"
[[ -f "$BACKUP_KEY.pub" ]] || die "no $BACKUP_KEY.pub; run 'sudo ./backup.sh keys' here first (cellar backs itself up through this account too)."

# ── the keys, checked before anything changes ────────────────────────────────
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
count=0
add_key() {  # add_key <node> <ip> <key>
  printf 'from="%s",restrict %s\n' "$2" "$3" >> "$tmp"
  note "$1: may use the repository from $2"
  count=$((count + 1))
}
add_key "$NODE_NAME" "$NODE_IP" "$(cat "$BACKUP_KEY.pub")"
if [[ -f "$KEYS" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    read -r node from key <<< "$line" || true
    [[ -n "${node:-}" ]] || continue
    [[ -f "$NODES/$node/node.conf" ]] || die "backup.keys: '$node' isn't a node in nodes/."
    [[ "$node" != "$NODE_NAME" ]] || die "backup.keys: $NODE_NAME is the hub; its own key is added without a line."
    [[ "$from" =~ ^from=\"([0-9.]+)\"$ ]] || die "backup.keys: $node's line needs from=\"<ip>\" second, as 'backup.sh keys' prints it."
    [[ "$key" == ssh-ed25519\ * ]] || die "backup.keys: $node's key isn't an ssh-ed25519 public key."
    add_key "$node" "${BASH_REMATCH[1]}" "$key"
  done < "$KEYS"
else
  warn "no $KEYS yet: only $NODE_NAME itself can reach the repository until it's there."
fi
if [[ $CHECK -eq 1 ]]; then
  echo
  echo "Would write $HOME_DIR/.ssh/authorized_keys for $USER_NAME (chroot $CHROOT, repository $REPO_DIR):"
  cat "$tmp"
  exit 0
fi

# ── account and folders ──────────────────────────────────────────────────────
if ! id "$USER_NAME" >/dev/null 2>&1; then
  # No password and no shell: the key is the only way in, and sshd's
  # ForceCommand internal-sftp never starts a shell anyway.
  useradd --system --home-dir "$HOME_DIR" --create-home --shell /usr/sbin/nologin "$USER_NAME"
  note "made the $USER_NAME account"
fi
# sshd refuses a chroot that any part of, up to /, is writable by anyone
# but root. The repository folder inside it is the account's alone.
install -d -m 755 -o root -g root "$CHROOT"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$REPO_DIR"
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
install -m 600 -o "$USER_NAME" -g "$USER_NAME" "$tmp" "$HOME_DIR/.ssh/authorized_keys"
note "$REPO_DIR: the repository folder ($USER_NAME's; nodes see it as $REPO_PATH)"

# ── sshd ─────────────────────────────────────────────────────────────────────
# Its own drop-in, beside dump-store-setup.sh's, so neither rewrites the
# other's or the bootstrap's. AllowUsers lines add up, if the bootstrap set one.
DROPIN=/etc/ssh/sshd_config.d/20-purrbrews-repo.conf
want="$(printf '%s\n' \
  '# Written by stacks/backup/restic/repo-setup.sh: the restic repository,' \
  '# reached over SFTP by every node with its backup key, and nothing else.' \
  "AllowUsers $USER_NAME" \
  "Match User $USER_NAME" \
  "    ChrootDirectory $CHROOT" \
  '    ForceCommand internal-sftp' \
  '    PasswordAuthentication no' \
  '    AllowTcpForwarding no' \
  '    AllowAgentForwarding no' \
  '    X11Forwarding no' \
  '    PermitTTY no')"
if [[ "$(cat "$DROPIN" 2>/dev/null)" != "$want" ]]; then
  backup_conf=''
  [[ -f "$DROPIN" ]] && { backup_conf="$DROPIN.bak-$(date +%Y%m%d%H%M%S)"; cp -p "$DROPIN" "$backup_conf"; }
  printf '%s\n' "$want" > "$DROPIN"
  chmod 644 "$DROPIN"
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    note "sshd: $USER_NAME allowed in, chrooted to $CHROOT ($DROPIN), reloaded"
  else
    if [[ -n "$backup_conf" ]]; then mv -f "$backup_conf" "$DROPIN"; else rm -f "$DROPIN"; fi
    die "sshd -t rejected $DROPIN; put back as it was. Nothing reloaded."
  fi
else
  note "sshd: $USER_NAME already set up ($DROPIN)"
fi
# Captured first: with pipefail, grep -q quitting early would SIGPIPE sshd
# and fail the pipeline even on a match.
effective="$(sshd -T -C "user=$USER_NAME,host=x,addr=$NODE_IP" 2>/dev/null || true)"
if ! grep -qiE "^chrootdirectory $CHROOT\$" <<< "$effective"; then
  warn "sshd -T doesn't show the chroot for $USER_NAME; check $DROPIN isn't overridden."
fi

echo
echo "Done: $count key(s) can reach the repository."
echo "Next, once: sudo ./restic/restic-init.sh. Then on each node: sudo ./backup.sh doctor"
