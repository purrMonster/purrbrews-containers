#!/usr/bin/env bash
# require-bundle.sh: called from the prepare.sh of an app whose SSL_CERT_FILE
# is this relay's bundle (the host's public roots plus the relay's CA):
#
#   require-bundle.sh <app> <DATA_DIR>
#
# Without that file the app trusts nothing, so its Authelia (OIDC) login and
# every other HTTPS call break too, not just mail. prepare.sh in this folder
# makes it; bring the relay up first.
set -euo pipefail
app="${1:?usage: require-bundle.sh <app> <DATA_DIR>}"
DATA_DIR="${2:?usage: require-bundle.sh <app> <DATA_DIR>}"
SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)
if ! "${SUDO[@]}" test -s "$DATA_DIR/mail-relay/tls-public/bundle.crt"; then
  echo "$app/prepare.sh: no $DATA_DIR/mail-relay/tls-public/bundle.crt; run ./compose.sh mail-relay up -d first (mail-relay/README.md)." >&2
  exit 1
fi
