#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. A newer Meilisearch can't open an
# older index, so with an index already there a new version starts only once
# it's acknowledged. The steps are in docs/image-upgrades.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../../_lib/upgrade-gate.sh" "$here" "${1:?usage: prepare.sh <DATA_DIR>}" \
  karakeep-meilisearch/data.ms KARAKEEP_SEARCH_UPGRADE_READY getmeili/meilisearch
