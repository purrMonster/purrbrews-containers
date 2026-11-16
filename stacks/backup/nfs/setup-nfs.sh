#!/usr/bin/env bash
#
# setup-nfs.sh: export MEDIA_DIR/archive over NFS to the LAN, as a plain host
# service. Not a container on purpose: the usual NFS server image is
# abandoned and wants --privileged, a far bigger grant than the job needs.
#
# Safe to re-run: it owns one marked block in /etc/exports and replaces only
# that. Nothing mounts this yet.
#
#   sudo ./nfs/setup-nfs.sh
#
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run it with sudo."

command -v exportfs >/dev/null || { apt-get update && apt-get install -y nfs-kernel-server; }

ARCHIVE="$(env_value MEDIA_DIR)/archive"
LAN_CIDR="$(env_value LAN_CIDR)"
[[ -n "$LAN_CIDR" && "$ARCHIVE" != /archive ]] || die "MEDIA_DIR or LAN_CIDR isn't set."

# All access is squashed to the ops user (PUID:PGID, which init writes to
# /opt/purrbrews/.env from barista's real uid), also the SMB share's UID_barista,
# so files written over NFS and SMB agree on an owner. Not 1000: on a node whose
# installer account took 1000, barista is 1001.
PUID="$(env_value PUID)"; PGID="$(env_value PGID)"
[[ "$PUID" =~ ^[0-9]+$ && "$PGID" =~ ^[0-9]+$ ]] || die "PUID/PGID aren't set (/opt/purrbrews/.env, from init)."
mkdir -p "$ARCHIVE"
chown -R "$PUID:$PGID" "$ARCHIVE"

START="# --- purrbrews cellar NFS exports (managed by setup-nfs.sh) ---"
END="# --- end purrbrews cellar NFS exports ---"
if grep -qF "$START" /etc/exports 2>/dev/null; then
  sed -i "/^${START}\$/,/^${END}\$/d" /etc/exports
fi
{
  echo "$START"
  echo "$ARCHIVE $LAN_CIDR(rw,sync,no_subtree_check,all_squash,anonuid=$PUID,anongid=$PGID)"
  echo "$END"
} >> /etc/exports

exportfs -ra
systemctl enable --now nfs-kernel-server
echo "Exported $ARCHIVE to $LAN_CIDR. Check with: showmount -e localhost"
