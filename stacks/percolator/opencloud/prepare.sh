#!/usr/bin/env bash
# OpenCloud major upgrades can migrate persisted state one way.
# Acknowledgement follows a verified backup and the documented upgrade steps.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../../_lib/upgrade-gate.sh" "$here" "${1:?usage: prepare.sh <DATA_DIR>}" \
  opencloud/config/opencloud.yaml OPENCLOUD_UPGRADE_READY opencloudeu/opencloud major
