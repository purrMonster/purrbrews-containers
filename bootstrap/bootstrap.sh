#!/usr/bin/env bash
#
# bootstrap.sh — served by purrbrews-bootstrap on roastery. On a fresh node:
#
#   wget -qO- --no-check-certificate https://<roastery-ip>:8443/bootstrap.sh | sudo bash -s -- <node> [init options]
#
# (curl works too:  curl -kfsSL https://<roastery-ip>:8443/bootstrap.sh | sudo bash -s -- <node>)
#
# What it does:
#   1. Pins roastery's TLS key. Pass PB_PIN=sha256//... (from 'docker compose logs')
#      to verify it strictly; otherwise it shows the pin and asks you to confirm
#      it matches (trust on first use). Everything after this uses the pin.
#   2. Downloads the init scripts and checks them against SHA256SUMS.
#   3. Downloads the fleet settings (purrbrews-init.env — nothing secret in it).
#   4. Points SSH key sync at roastery (pinned) and runs purrbrews-init.sh.
#   The only thing you type is barista's sudo password, at the node's console.
#
# Environment (all optional):
#   PB_PIN=sha256//...   expected TLS public-key pin (skip the confirmation)
#
set -Eeuo pipefail

# Everything is inside { ... } so bash reads the whole script before running any
# of it — required when the script itself arrives on stdin through a pipe.
{
BASE_URL="__PURRBREWS_BASE_URL__"      # filled in by nginx for each request
WORK="/root/purrbrews-bootstrap"

have_tty() { { : < /dev/tty; } 2>/dev/null; }
say()  { printf '\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[bootstrap] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run as root: ... | sudo bash -s -- <node>"
[[ "$BASE_URL" == https://* ]] || die "Base URL was not filled in ('$BASE_URL'). Download this script from the bootstrap server, not from the repo."

AUTO_YES=false
for a in "$@"; do [[ "$a" == --yes || "$a" == -y ]] && AUTO_YES=true; done

hostport="${BASE_URL#https://}"; hostport="${hostport%%/*}"
host="${hostport%:*}"; port="${hostport##*:}"
[[ "$host" == "$port" ]] && port=443
host="${host#[}"; host="${host%]}"

# --- prerequisites ------------------------------------------------------------
need=()
for c in curl:curl openssl:openssl sha256sum:coreutils; do
  command -v "${c%%:*}" &>/dev/null || need+=("${c##*:}")
done
if [[ ${#need[@]} -gt 0 ]]; then
  say "Installing ${need[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates "${need[@]}" >/dev/null
fi

# --- 1. pin roastery's TLS key ---------------------------------------------------
seen_pin="$(openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout 2>/dev/null \
  | openssl pkey -pubin -outform der 2>/dev/null \
  | openssl dgst -sha256 -binary | openssl base64 -A)"
[[ -n "$seen_pin" && "$seen_pin" != "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" ]] \
  || die "Could not read a TLS key from ${host}:${port}."
PIN="sha256//${seen_pin}"

if [[ -n "${PB_PIN:-}" ]]; then
  [[ "$PB_PIN" == "$PIN" ]] || die "TLS pin mismatch! expected $PB_PIN, server presented $PIN. Not continuing."
  say "TLS pin verified: $PIN"
else
  say "roastery presented TLS pin:  $PIN"
  say "It must match the pin in 'docker compose logs bootstrap' on roastery."
  if ! $AUTO_YES; then
    have_tty || die "No terminal to confirm the pin. Re-run with PB_PIN=$PIN"
    read -r -p "Does it match? [y/N] " ans < /dev/tty
    [[ "$ans" =~ ^[Yy]$ ]] || die "Pin not confirmed."
  fi
fi

fetch() {  # fetch <path> <out> [extra curl args...]
  local path="$1" out="$2"; shift 2
  curl -fsS --retry 3 --retry-delay 2 --max-time 60 -k --pinnedpubkey "$PIN" "$@" \
       -o "$out" "${BASE_URL}${path}"
}

# --- 2. scripts ----------------------------------------------------------------
rm -rf "$WORK"; install -d -m 700 "$WORK" "$WORK/lib"

fetch /files/SHA256SUMS "$WORK/SHA256SUMS"
while read -r _sum file; do
  [[ "$file" =~ ^[A-Za-z0-9._/-]+$ && "$file" != *..* ]] || die "Refusing odd path in SHA256SUMS: $file"
  install -d -m 700 "$WORK/$(dirname "$file")"
  fetch "/files/$file" "$WORK/$file"
done < "$WORK/SHA256SUMS"
( cd "$WORK" && sha256sum --quiet -c SHA256SUMS ) || die "Checksum mismatch on downloaded scripts."
say "Downloaded and verified $(wc -l < "$WORK/SHA256SUMS") files."

# --- 3. settings -----------------------------------------------------------------
fetch /config/purrbrews-init.env "$WORK/purrbrews-init.env"
chmod 600 "$WORK/purrbrews-init.env"
grep -E '^[[:space:]]*(OPS_PASSWORD_HASH|GITHUB_TOKEN)[[:space:]]*=[[:space:]]*[^[:space:]]' "$WORK/purrbrews-init.env" \
  | grep -vq 'REPLACE_ME' && die "The served settings contain a secret (OPS_PASSWORD_HASH/GITHUB_TOKEN). Remove it from bootstrap/data on roastery."

# Later lines win in the env parser: make key sync use roastery, pinned.
{
  printf '\n# --- added by bootstrap.sh ---\n'
  printf 'BOOTSTRAP_URL=%s\n' "$BASE_URL"
  printf 'SSH_KEYS_URLS=%s/keys/authorized_keys\n' "$BASE_URL"
  printf 'SSH_KEYS_PINNED_PUBKEY=%s\n' "$PIN"
} >> "$WORK/purrbrews-init.env"

# --- 4. run init ---------------------------------------------------------------
say "Starting purrbrews-init.sh $*"
rc=0
PURRBREWS_BOOTSTRAP=1 bash "$WORK/purrbrews-init.sh" --env "$WORK/purrbrews-init.env" "$@" < /dev/null || rc=$?
exit "$rc"
}
