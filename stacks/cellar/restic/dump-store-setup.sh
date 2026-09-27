#!/usr/bin/env bash
#
# dump-store-setup.sh: make cellar the dump store the other nodes push to.
# Safe to re-run; run it again whenever restic/dump-store.keys changes.
#
#   - a `dumps` system account, which only ever runs rrsync;
#   - DUMP_DIR/<node>/ for every node that's listed, owned by it;
#   - `AllowUsers dumps` in an sshd drop-in (init allows barista only);
#   - its authorized_keys, rebuilt from restic/dump-store.keys: each node's
#     key pinned to that node's address and locked into its own folder by
#     `rrsync -wo <DUMP_DIR>/<node>`: it can write its own folder and
#     nothing else (not read it back, not another node's, not a shell).
#
# restic/dump-store.keys (gitignored; copy dump-store.keys.example) has one
# line per node, exactly what `sudo ./backup.sh keys` printed on that node:
#
#   <node> from="<ip>" ssh-ed25519 AAAA... purrbrews-backup@<node>
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: it makes an account and writes its authorized_keys."
KEYS="$DIR/dump-store.keys"
[[ -f "$KEYS" ]] || die "no $KEYS; copy dump-store.keys.example and add each node's line from 'backup.sh keys'."
RRSYNC="$(command -v rrsync || true)"
[[ -n "$RRSYNC" ]] || die "rrsync isn't installed (it comes with rsync on Debian 12+: apt install rsync)."
DUMP_DIR="$(env_value DUMP_DIR)"; DUMP_DIR="${DUMP_DIR:-/srv/dumps}"
USER_NAME=dumps
HOME_DIR=/var/lib/purrbrews-dumps

# ── account ──────────────────────────────────────────────────────────────────
if ! id "$USER_NAME" >/dev/null 2>&1; then
  # A real shell, because sshd runs the forced command through it; no
  # password, so the key is the only way in.
  useradd --system --home-dir "$HOME_DIR" --create-home --shell /bin/sh "$USER_NAME"
  note "made the $USER_NAME account"
fi
install -d -m 755 -o root -g root "$DUMP_DIR"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"

# ── keys ─────────────────────────────────────────────────────────────────────
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  read -r node from key <<< "$line" || true
  [[ -n "${node:-}" ]] || continue
  [[ -f "$STACKS/$node/node.conf" ]] || die "dump-store.keys: '$node' isn't a node in stacks/."
  [[ "$node" != "$NODE_NAME" ]] || die "dump-store.keys: $NODE_NAME is the store itself; it writes its dumps directly."
  [[ "$from" =~ ^from=\"[0-9.]+\"$ ]] || die "dump-store.keys: $node's line needs from=\"<ip>\" second, as 'backup.sh keys' prints it."
  [[ "$key" == ssh-ed25519\ * ]] || die "dump-store.keys: $node's key isn't an ssh-ed25519 public key."
  install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$DUMP_DIR/$node"
  printf 'command="%s -wo %s/%s",%s,restrict %s\n' "$RRSYNC" "$DUMP_DIR" "$node" "$from" "$key" >> "$tmp"
  note "$node: may write $DUMP_DIR/$node from ${from#from=}"
  count=$((count + 1))
done < "$KEYS"
[[ $count -gt 0 ]] || die "dump-store.keys has no node lines."
install -m 600 -o "$USER_NAME" -g "$USER_NAME" "$tmp" "$HOME_DIR/.ssh/authorized_keys"

# ── sshd ─────────────────────────────────────────────────────────────────────
# init's 00-purrbrews.conf has `AllowUsers barista`, so sshd turns dumps away
# until it's allowed too (AllowUsers lines add up). Its own drop-in, so
# init's file stays init's, and the rest of the account's limits come from
# the forced command in authorized_keys.
DROPIN=/etc/ssh/sshd_config.d/20-purrbrews-dumps.conf
want="$(printf '%s\n' \
  '# Written by stacks/cellar/restic/dump-store-setup.sh: the nodes push their' \
  '# database dumps here as dumps, a key-only account locked to rrsync.' \
  "AllowUsers $USER_NAME" \
  "Match User $USER_NAME" \
  '    PasswordAuthentication no' \
  '    AllowTcpForwarding no' \
  '    X11Forwarding no' \
  '    PermitTTY no')"
if [[ "$(cat "$DROPIN" 2>/dev/null)" != "$want" ]]; then
  backup_conf=''
  [[ -f "$DROPIN" ]] && { backup_conf="$DROPIN.bak-$(date +%Y%m%d%H%M%S)"; cp -p "$DROPIN" "$backup_conf"; }
  printf '%s\n' "$want" > "$DROPIN"
  chmod 644 "$DROPIN"
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    note "sshd: $USER_NAME allowed in ($DROPIN), reloaded"
  else
    if [[ -n "$backup_conf" ]]; then mv -f "$backup_conf" "$DROPIN"; else rm -f "$DROPIN"; fi
    die "sshd -t rejected $DROPIN; put back as it was. Nothing reloaded."
  fi
else
  note "sshd: $USER_NAME already allowed in ($DROPIN)"
fi
if ! sshd -T -C "user=$USER_NAME,host=x,addr=${DUMP_STORE_CHECK_ADDR:-192.168.0.11}" 2>/dev/null | grep -qiE "^allowusers .*\b$USER_NAME\b"; then
  warn "sshd -T still doesn't list $USER_NAME under AllowUsers; the nodes won't get in."
fi

echo
echo "Done: $count node(s) can push. On each, check with: sudo ./backup.sh doctor"
