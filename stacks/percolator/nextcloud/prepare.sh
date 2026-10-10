#!/usr/bin/env bash
# Prevent an ordinary restart from silently crossing an unreviewed major upgrade.
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../_lib/common.sh"
load_node "$(dirname "${BASH_SOURCE[0]}")/.."
SUDO=()
if [[ $EUID -ne 0 ]]; then SUDO=(sudo); fi
present="$("${SUDO[@]}" bash -c 'if [[ -e "$1" ]]; then printf yes; fi' _ \
  "${1:?DATA_DIR required}/nextcloud/html/config/config.php")" || die "Cannot inspect existing Nextcloud data."
if [[ "$present" == yes ]]; then
  [[ "$(env_value NEXTCLOUD_UPGRADE_READY)" == 35.0.1 ]] || die \
    "Existing Nextcloud data: complete docs/image-upgrades.md, then set NEXTCLOUD_UPGRADE_READY=35.0.1 in the node's .env.local."
fi
