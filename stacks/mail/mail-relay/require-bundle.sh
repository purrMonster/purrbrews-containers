#!/usr/bin/env bash
# require-bundle.sh: called from the prepare.sh of an app whose SSL_CERT_FILE
# is this relay's bundle (the host's public roots plus the relay's CA):
#
#   require-bundle.sh <app> <DATA_DIR>
#
# Without that file the app trusts nothing, so its Authelia (OIDC) login and
# every other HTTPS call break too, not just mail.
#
# On percolator, the relay's own prepare.sh makes the bundle: bring the relay
# up first. On another node (Paperless on grinder, since 2026-11-23) there is
# no relay, only a copy of its public ca.crt in the same place
# (mail-relay/README.md, "Another node's app"); this script then makes the
# bundle from this host's roots and that copy, again on every run, so it stays
# as current as the host's ca-certificates.
set -euo pipefail
app="${1:?usage: require-bundle.sh <app> <DATA_DIR>}"
DATA_DIR="${2:?usage: require-bundle.sh <app> <DATA_DIR>}"
PUB="$DATA_DIR/mail-relay/tls-public"
SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

# Not the relay's node (no private tls/ here), but a copied ca.crt: make the
# bundle from it. Anywhere else, the relay's prepare.sh made it.
if ! "${SUDO[@]}" test -d "$DATA_DIR/mail-relay/tls" && "${SUDO[@]}" test -s "$PUB/ca.crt"; then
  roots=/etc/ssl/certs/ca-certificates.crt
  [[ -s "$roots" ]] || { echo "$app/prepare.sh: no $roots on this host (apt install ca-certificates)." >&2; exit 1; }
  tmpb="$(mktemp)"; trap 'rm -f "$tmpb"' EXIT
  cat "$roots" > "$tmpb"
  "${SUDO[@]}" cat "$PUB/ca.crt" >> "$tmpb"
  if ! "${SUDO[@]}" cmp -s "$tmpb" "$PUB/bundle.crt"; then
    "${SUDO[@]}" install -m 644 "$tmpb" "$PUB/bundle.crt"   # root:root under sudo
  fi
fi

if ! "${SUDO[@]}" test -s "$PUB/bundle.crt"; then
  echo "$app/prepare.sh: no $PUB/bundle.crt. On percolator, run ./compose.sh mail-relay up -d first; on another node, copy the relay's ca.crt to $PUB/ first (mail-relay/README.md, \"Another node's app\")." >&2
  exit 1
fi
