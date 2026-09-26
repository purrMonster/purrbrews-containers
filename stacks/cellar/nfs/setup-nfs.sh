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

# All access is squashed to UID 1000, the ops user on every node and the SMB
# share's UID_barista, so files written over NFS and SMB agree on an owner.
mkdir -p "$ARCHIVE"
chown -R 1000:1000 "$ARCHIVE"

START="# --- purrbrews cellar NFS exports (managed by setup-nfs.sh) ---"
END="# --- end purrbrews cellar NFS exports ---"
if grep -qF "$START" /etc/exports 2>/dev/null; then
  sed -i "/^${START}\$/,/^${END}\$/d" /etc/exports
fi
{
  echo "$START"
  echo "$ARCHIVE $LAN_CIDR(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)"
  echo "$END"
} >> /etc/exports

exportfs -ra
systemctl enable --now nfs-kernel-server
echo "Exported $ARCHIVE to $LAN_CIDR. Check with: showmount -e localhost"
