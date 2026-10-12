#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. Vaultwarden's SSL_CERT_FILE is
# mail-relay's bundle (the host's public roots plus the relay's CA). Without
# that file Vaultwarden trusts nothing, so its Authelia (OIDC) login breaks
# too, not just mail. mail-relay/prepare.sh makes it; bring that up first.
set -euo pipefail
DATA_DIR="${1:?usage: prepare.sh <DATA_DIR>}"
SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)
if ! "${SUDO[@]}" test -s "$DATA_DIR/mail-relay/tls-public/bundle.crt"; then
  echo "vaultwarden/prepare.sh: no $DATA_DIR/mail-relay/tls-public/bundle.crt; run ./compose.sh mail-relay up -d first (mail-relay/README.md)." >&2
  exit 1
fi
