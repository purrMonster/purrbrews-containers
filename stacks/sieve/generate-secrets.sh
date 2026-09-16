#!/usr/bin/env bash
#
# generate-secrets.sh — create every secret sieve's apps need, on sieve itself,
# into gitignored <app>/secrets.env.local files (mode 600).
#
# Idempotent: a key that already has a real value is never changed. Re-run it
# any time; run it after pulling a change that adds a secret.
#
# Values that can't be generated are asked for (input hidden). Leave one blank
# to skip it for now: it keeps a REPLACE_ME placeholder and is asked again next
# run. Without a terminal nothing is asked.
#
# Run as barista, NOT with sudo — sudo would leave root-owned files that break the
# next run. The one step that needs Docker (bcrypt hashing) uses sudo itself.
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NTFY_IMAGE="binwiederhier/ntfy:v2.28.0"   # keep in step with ntfy/docker-compose.yml

[[ $EUID -ne 0 ]] || { echo "Run as your ops user, not root/sudo." >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl is required." >&2; exit 1; }

# Hex only: no + / = to break URLs, headers or env parsing.
rand() { openssl rand -hex "${1:-32}"; }
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

ensure_file() { [[ -f "$1" ]] || { umask 077; : > "$1"; }; chmod 600 "$1"; }

get_value() {  # get_value <file> <KEY> — raw value, surrounding single quotes removed
  local line
  [[ -f "$1" ]] || return 0
  line="$(grep -E "^$2=" "$1" | tail -n1 || true)"
  line="${line#*=}"; line="${line#\'}"; line="${line%\'}"
  printf '%s' "$line"
}

is_set() { local v; v="$(get_value "$1" "$2")"; [[ -n "$v" && "$v" != *REPLACE_ME* ]]; }

put_value() {  # put_value <file> <KEY> <value> — replace or append, single-quoted
  local file="$1" key="$2" value="$3" tmp
  [[ "$value" != *"'"* ]] || { echo "Refusing a value with a single quote for $key." >&2; exit 1; }
  ensure_file "$file"
  tmp="$(mktemp "${file}.XXXX")"
  if grep -qE "^${key}=" "$file"; then   # replace in place, keeping line order
    KEY="$key" VAL="'${value}'" awk 'index($0, ENVIRON["KEY"]"=")==1 {print ENVIRON["KEY"]"="ENVIRON["VAL"]; next} {print}' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"; printf "%s='%s'\n" "$key" "$value" >> "$tmp"
  fi
  chmod 600 "$tmp"; mv "$tmp" "$file"
}

set_if_absent() { is_set "$1" "$2" || put_value "$1" "$2" "$3"; }

prompt_secret() {  # prompt_secret <file> <KEY> <prompt> <placeholder>
  local file="$1" key="$2" text="$3" placeholder="$4" value=""
  is_set "$file" "$key" && return 0
  if [[ -t 0 ]]; then
    read -r -s -p "  ${text}: " value; printf '\n'
  fi
  if [[ -z "$value" ]]; then
    [[ -t 0 ]] && echo "    (skipped — re-run once you have it)"
    value="$placeholder"
  fi
  put_value "$file" "$key" "$value"
}

# shellcheck disable=SC2016  # literal $ in the regex
bcrypt() {  # bcrypt <password> — ntfy's own hasher, so the format is exactly what it expects
  printf '%s\n%s\n' "$1" "$1" \
    | sudo docker run --rm -i "$NTFY_IMAGE" user hash 2>/dev/null \
    | grep -oE '\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}' | head -n1
}

ntfy_token() { printf 'tk_%s' "$(rand 16 | cut -c1-29)"; }   # tk_ + 29 = 32 chars

# ── ntfy ──────────────────────────────────────────────────────────────────────
log "ntfy/secrets.env.local"
NTFY="${DIR}/ntfy/secrets.env.local"
ensure_file "$NTFY"

# Topic names aren't secret here (access is deny-all), just fixed.
set_if_absent "$NTFY" NTFY_ALERT_TOPIC "purrbrews-alerts"
set_if_absent "$NTFY" NTFY_ADMIN_USER  "barista"
# Password you type into the ntfy app on each phone. 16 bytes, still typeable.
# To change it: set a new value and delete NTFY_ADMIN_HASH, then re-run.
set_if_absent "$NTFY" NTFY_ADMIN_PASSWORD "$(rand 16)"
# Gatus publishes with a token; its user's password is never used.
set_if_absent "$NTFY" NTFY_GATUS_PASSWORD "$(rand 32)"
set_if_absent "$NTFY" GATUS_NTFY_TOKEN "$(ntfy_token)"

for who in ADMIN GATUS; do
  if ! is_set "$NTFY" "NTFY_${who}_HASH"; then
    echo "  bcrypt-hashing the ${who,,} password (sudo docker run ${NTFY_IMAGE})…"
    hash="$(bcrypt "$(get_value "$NTFY" "NTFY_${who}_PASSWORD")")"
    if [[ -n "$hash" ]]; then put_value "$NTFY" "NTFY_${who}_HASH" "$hash"
    else echo "  ! couldn't hash with Docker — is it installed? Re-run." >&2; fi
  fi
done

# Your own additions, kept across runs. Comma-separated, same formats as ntfy:
#   NTFY_EXTRA_USERS   name:bcrypt-hash:role     NTFY_EXTRA_ACCESS  name:topic:rw|ro|wo
#   NTFY_EXTRA_TOKENS  name:tk_…:label
for k in NTFY_EXTRA_USERS NTFY_EXTRA_ACCESS NTFY_EXTRA_TOKENS; do
  grep -qE "^${k}=" "$NTFY" || put_value "$NTFY" "$k" ""
done
with_extra() { local extra; extra="$(get_value "$NTFY" "$2")"; printf '%s%s' "$1" "${extra:+,$extra}"; }

# What ntfy reads — rebuilt every run from the values above, so never edit these.
if is_set "$NTFY" NTFY_ADMIN_HASH && is_set "$NTFY" NTFY_GATUS_HASH; then
  put_value "$NTFY" NTFY_AUTH_USERS "$(with_extra \
    "$(get_value "$NTFY" NTFY_ADMIN_USER):$(get_value "$NTFY" NTFY_ADMIN_HASH):admin,gatus:$(get_value "$NTFY" NTFY_GATUS_HASH):user" \
    NTFY_EXTRA_USERS)"
fi
put_value "$NTFY" NTFY_AUTH_ACCESS "$(with_extra "gatus:$(get_value "$NTFY" NTFY_ALERT_TOPIC):wo" NTFY_EXTRA_ACCESS)"
put_value "$NTFY" NTFY_AUTH_TOKENS "$(with_extra "gatus:$(get_value "$NTFY" GATUS_NTFY_TOKEN):gatus" NTFY_EXTRA_TOKENS)"

# ── gatus ─────────────────────────────────────────────────────────────────────
log "gatus/secrets.env.local"
GATUS="${DIR}/gatus/secrets.env.local"
ensure_file "$GATUS"
# Same node as ntfy, so copied straight across.
put_value "$GATUS" NTFY_ALERT_TOPIC "$(get_value "$NTFY" NTFY_ALERT_TOPIC)"
put_value "$GATUS" GATUS_NTFY_TOKEN "$(get_value "$NTFY" GATUS_NTFY_TOKEN)"
# Public ntfy.sh topic for critical alerts. Anyone who knows the name can read
# it, so it is long and random — treat it like a password.
set_if_absent "$GATUS" NTFY_CRITICAL_TOPIC "purrbrews-$(rand 12)"
prompt_secret "$GATUS" HEALTHCHECKS_PING_URL \
  "healthchecks.io ping URL (https://hc-ping.com/…)" "https://hc-ping.com/REPLACE_ME"

# ── traefik ───────────────────────────────────────────────────────────────────
log "traefik/secrets.env.local"
# Cloudflare API token for DNS-01 certificates. Create it with the "Edit zone DNS"
# template, scoped to your zone only. The same token works on every node.
prompt_secret "${DIR}/traefik/secrets.env.local" CF_DNS_API_TOKEN \
  "Cloudflare API token (Zone → DNS → Edit, your zone only)" "REPLACE_ME"

# ── cloudflared ───────────────────────────────────────────────────────────────
log "cloudflared/secrets.env.local"
prompt_secret "${DIR}/cloudflared/secrets.env.local" TUNNEL_TOKEN \
  "Cloudflare Tunnel token (Zero Trust → Networks → Tunnels → sieve)" "REPLACE_ME"

# pihole, unbound, netalertx: no secrets.

# ── Summary ───────────────────────────────────────────────────────────────────
log "Summary"
missing=()
# shellcheck disable=SC2094  # read-only loop; the filename is only printed
for f in "${DIR}"/*/secrets.env.local; do
  while IFS= read -r line; do
    [[ "$line" == *REPLACE_ME* ]] && missing+=("$(basename "$(dirname "$f")")/secrets.env.local: ${line%%=*}")
  done < "$f"
done
is_set "$NTFY" NTFY_AUTH_USERS || missing+=("ntfy/secrets.env.local: NTFY_AUTH_USERS (bcrypt hashing via Docker failed)")

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "All secrets are set."
else
  echo "Still needed (re-run this script once you have them):"
  printf '  - %s\n' "${missing[@]}"
fi
cat <<INFO

Phone setup (ntfy app):
  server   https://ntfy.<DOMAIN>
  user     $(get_value "$NTFY" NTFY_ADMIN_USER)   password in ntfy/secrets.env.local (NTFY_ADMIN_PASSWORD)
  topics   $(get_value "$NTFY" NTFY_ALERT_TOPIC) on that server,
           and the critical topic on https://ntfy.sh (NTFY_CRITICAL_TOPIC in gatus/secrets.env.local)
INFO
[[ ${#missing[@]} -eq 0 ]]
