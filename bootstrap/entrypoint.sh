#!/bin/sh
#
# Runs inside the nginx image before nginx starts (/docker-entrypoint.d/).
#   - creates a self-signed TLS key/cert once, kept in the "certs" volume so
#     its fingerprint (which nodes pin) survives rebuilds
#   - checks bootstrap/data is mounted and prints the pin nodes should see
#
set -eu

say() { echo "[purrbrews-bootstrap] $*"; }
fail() { echo "[purrbrews-bootstrap] ERROR: $*" >&2; exit 1; }

# --- TLS ---------------------------------------------------------------------
if [ ! -s /certs/bootstrap.key ] || [ ! -s /certs/bootstrap.crt ]; then
  say "Generating TLS key and self-signed certificate (one time)"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout /certs/bootstrap.key -out /certs/bootstrap.crt -days 3650 \
    -subj "/CN=purrbrews-bootstrap" \
    -addext "subjectAltName=DNS:roastery,DNS:roastery.lan,DNS:localhost" 2>/dev/null
  chmod 600 /certs/bootstrap.key
fi
PIN="$(openssl x509 -in /certs/bootstrap.crt -pubkey -noout \
       | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64 -A)"

# --- data ----------------------------------------------------------------------
[ -f /data/authorized_keys ] || fail "bootstrap/data/authorized_keys is missing (one public key per line)."
grep -Eq '^(ssh-|ecdsa-|sk-)' /data/authorized_keys || fail "bootstrap/data/authorized_keys contains no public keys."
if grep -q 'PRIVATE KEY' /data/authorized_keys; then fail "bootstrap/data/authorized_keys contains a PRIVATE key. Remove it."; fi
[ -f /data/purrbrews-init.env ] || fail "bootstrap/data/purrbrews-init.env is missing (copy init/purrbrews-init.env.example)."
# Everything here is served without authentication: refuse to start with a secret in it.
# (An empty value or a REPLACE_ME placeholder is fine.)
if grep -E '^[[:space:]]*(OPS_PASSWORD_HASH|GITHUB_TOKEN)[[:space:]]*=[[:space:]]*[^[:space:]]' /data/purrbrews-init.env \
   | grep -vq 'REPLACE_ME'; then
  fail "bootstrap/data/purrbrews-init.env contains OPS_PASSWORD_HASH or GITHUB_TOKEN. It is served openly — remove them."
fi
if grep -q 'PRIVATE KEY' /data/purrbrews-init.env; then fail "bootstrap/data/purrbrews-init.env contains a private key."; fi

KEYS="$(grep -Ec '^(ssh-|ecdsa-|sk-)' /data/authorized_keys)"
say "Serving $(wc -l < /srv/www/files/SHA256SUMS) script files, $KEYS SSH key(s), fleet settings."
say "TLS pin — compare with what a node prints:  sha256//$PIN"
say "On a node:  wget -qO- --no-check-certificate https://<roastery-ip>:${BOOTSTRAP_PORT:-8443}/bootstrap.sh | sudo bash -s -- <node>"
