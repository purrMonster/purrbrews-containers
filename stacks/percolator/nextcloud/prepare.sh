#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. Each Nextcloud major migrates its
# database one way, so with data already there a new major starts only once
# it's acknowledged. The steps are in docs/image-upgrades.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../../_lib/upgrade-gate.sh" "$here" "${1:?usage: prepare.sh <DATA_DIR>}" \
  nextcloud/html/config/config.php NEXTCLOUD_UPGRADE_READY nextcloud major
