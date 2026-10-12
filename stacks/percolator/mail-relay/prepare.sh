#!/usr/bin/env bash
#
# prepare.sh: run by compose.sh before `up`. Makes the relay's TLS
# certificate the first time, from a private CA, and never again:
#
#   ${DATA_DIR}/mail-relay/tls/          root only: ca.key, relay.key, relay.crt
#   ${DATA_DIR}/mail-relay/tls-public/   ca.crt, which clients trust (Authelia
#                                        mounts this folder as its certificates)
#                                        and bundle.crt, rebuilt on every run:
#                                        this host's public roots + ca.crt, for
#                                        apps that take one file (Vaultwarden's
#                                        SSL_CERT_FILE), so they keep trusting the
#                                        public internet too, as current as the
#                                        host's ca-certificates at the last `up`
#
# Ten years, no renewal to forget. The certificate names `mail-relay` (the
# proxy network) and percolator's LAN address (the other nodes).
# To replace it: delete both folders, `./compose.sh mail-relay up -d`, then
# recreate Authelia and Vaultwarden so they read the new CA.
set -euo pipefail

DATA_DIR="${1:?usage: prepare.sh <DATA_DIR>}"
PRIV="$DATA_DIR/mail-relay/tls"
PUB="$DATA_DIR/mail-relay/tls-public"
FLEET="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/fleet.env"
IP="$(sed -n 's/^PERCOLATOR_LAN_IP=//p' "$FLEET")"

SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

make_bundle() {
  local roots=/etc/ssl/certs/ca-certificates.crt tmpb
  [[ -s "$roots" ]] || { echo "mail-relay/prepare.sh: no $roots on this host; bundle.crt not made." >&2; return 0; }
  tmpb="$(mktemp)"
  cat "$roots" "$PUB/ca.crt" > "$tmpb"
  if ! "${SUDO[@]}" cmp -s "$tmpb" "$PUB/bundle.crt"; then
    "${SUDO[@]}" install -m 644 -o 0 -g 0 "$tmpb" "$PUB/bundle.crt"
  fi
  rm -f "$tmpb"
}

if "${SUDO[@]}" test -s "$PRIV/relay.crt" && "${SUDO[@]}" test -s "$PRIV/relay.key" && "${SUDO[@]}" test -s "$PUB/ca.crt"; then
  make_bundle
  exit 0
fi
command -v openssl >/dev/null || { echo "mail-relay/prepare.sh: openssl is needed (apt install openssl)." >&2; exit 1; }

echo "mail-relay/prepare.sh: making the relay's certificate (private CA, 10 years)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -sha256 \
  -keyout "$tmp/ca.key" -out "$tmp/ca.crt" -subj "/CN=purrBrews mail-relay CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl req -newkey rsa:3072 -nodes -keyout "$tmp/relay.key" -out "$tmp/relay.csr" \
  -subj "/CN=mail-relay" 2>/dev/null
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:mail-relay,IP:%s\n' "$IP" > "$tmp/ext"
openssl x509 -req -in "$tmp/relay.csr" -CA "$tmp/ca.crt" -CAkey "$tmp/ca.key" -CAcreateserial \
  -days 3650 -sha256 -extfile "$tmp/ext" -out "$tmp/relay.crt" 2>/dev/null

"${SUDO[@]}" install -d -m 700 -o 0 -g 0 "$PRIV"
"${SUDO[@]}" install -d -m 755 -o 0 -g 0 "$PUB"
"${SUDO[@]}" install -m 600 -o 0 -g 0 "$tmp/ca.key" "$tmp/relay.key" "$PRIV/"
"${SUDO[@]}" install -m 644 -o 0 -g 0 "$tmp/relay.crt" "$PRIV/"
"${SUDO[@]}" install -m 644 -o 0 -g 0 "$tmp/ca.crt" "$PUB/"
make_bundle
echo "mail-relay/prepare.sh: certificate ready; clients trust $PUB/ca.crt"
