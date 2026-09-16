#!/usr/bin/env bash
#
# setup-nfs.sh — host-native NFS export setup, deliberately NOT a
# container. Confirmed on the pre-restructure cellar build (2026-09-03)
# and unchanged here: containerized NFS servers are still not
# recommended for this fleet's purposes -- the common image
# (erichough/nfs-server) is effectively abandoned and needs
# --privileged/broad SYS_ADMIN, a much bigger grant than smb's image
# needs for the equivalent job. NFS runs as a plain host service instead,
# same category as this project's own SSH/UFW/systemd-timer pieces.
#
# Exports /srv/media/archive (percolator's/mochaPot's app archives --
# Immich originals, Paperless-ngx archive, Nextcloud cold storage --
# consumed via NFS by those apps once they're migrated into this repo and
# actually mount from it; /srv/media/household is SMB-only, for direct
# human/LAN browsing, not exported here).
#
# Usage: sudo ./setup-nfs.sh
#
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo ./setup-nfs.sh)." >&2; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v exportfs >/dev/null 2>&1 || {
  echo "Installing nfs-kernel-server..."
  apt-get update && apt-get install -y nfs-kernel-server
}

mkdir -p /srv/media/archive

# UID/GID gotcha, carried over from the pre-restructure build and still
# not fully reconciled: the UID exports run as here must match
# ../smb/docker-compose.yml's UID_barista (1000) and whatever UID
# percolator's/mochaPot's containers run as when they mount this over NFS
# -- otherwise SMB and NFS clients touching the same files get permission
# mismatches. 1000 is barista's own UID on every node in this fleet (see
# init/purrbrews-init.sh), so this should already line up -- confirmed
# only once a consuming app's own compose file is actually written.
chown -R 1000:1000 /srv/media/archive

# Exports file managed as a whole block, not appended to blindly -- rerun-safe.
EXPORT_LINE="/srv/media/archive ${CELLAR_LAN_SUBNET:-192.168.0.0/24}(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)"
MARKER_START="# --- purrbrews cellar NFS exports (managed by setup-nfs.sh) ---"
MARKER_END="# --- end purrbrews cellar NFS exports ---"

if grep -qF "$MARKER_START" /etc/exports 2>/dev/null; then
  # Replace the managed block in place.
  sed -i "/^${MARKER_START}\$/,/^${MARKER_END}\$/d" /etc/exports
fi
{
  echo "$MARKER_START"
  echo "$EXPORT_LINE"
  echo "$MARKER_END"
} >> /etc/exports

exportfs -ra
systemctl enable --now nfs-kernel-server

echo "Exported /srv/media/archive. Verify with: showmount -e localhost"
echo "CELLAR_LAN_SUBNET defaults to 192.168.0.0/24 -- set it explicitly in"
echo "../.env.local if this fleet's subnet ever changes."
