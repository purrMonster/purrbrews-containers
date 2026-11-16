#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. Open WebUI migrates its database
# on start, one way, so with data already there a new version starts only once
# it's acknowledged. The steps are in docs/image-upgrades.md.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../../_lib/upgrade-gate.sh" "$here" "${1:?usage: prepare.sh <DATA_DIR>}" \
  openwebui/webui.db OPENWEBUI_UPGRADE_READY ghcr.io/open-webui/open-webui
