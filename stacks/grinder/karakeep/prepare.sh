#!/usr/bin/env bash
# A Meilisearch version change needs a validated dump/import, not just a new image.
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../_lib/common.sh"
load_node "$(dirname "${BASH_SOURCE[0]}")/.."
SUDO=()
if [[ $EUID -ne 0 ]]; then SUDO=(sudo); fi
present="$("${SUDO[@]}" bash -c 'if [[ -e "$1" ]]; then printf yes; fi' _ \
  "${1:?DATA_DIR required}/karakeep-meilisearch/data.ms")" || die "Cannot inspect existing search data."
if [[ "$present" == yes ]]; then
  [[ "$(env_value KARAKEEP_SEARCH_UPGRADE_READY)" == 1.54.3 ]] || die \
    "Existing search index: complete docs/image-upgrades.md, then set KARAKEEP_SEARCH_UPGRADE_READY=1.54.3 in the node's .env.local."
fi
