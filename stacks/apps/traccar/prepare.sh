#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. Traccar migrates its H2 database
# on start, one way, so with data already there a new version starts only once
# it's acknowledged. The steps are in docs/image-upgrades.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../../_lib/upgrade-gate.sh" "$here" "${1:?usage: prepare.sh <DATA_DIR>}" \
  traccar/data/database.mv.db TRACCAR_UPGRADE_READY traccar/traccar
