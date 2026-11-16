#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. Vaultwarden's SSL_CERT_FILE is
# mail-relay's bundle; refuse to start without it (mail-relay/require-bundle.sh).
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../mail-relay/require-bundle.sh" vaultwarden "${1:?usage: prepare.sh <DATA_DIR>}"
