#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret mochaPot's apps need, at
# runtime, on the node itself. Same mechanics as every other node's copy.
#
# Rebuilt from scratch 2026-09-16 for mochaPot's post-restructure app list
# (Home Assistant + PG, Music Assistant, Pi-hole secondary, kiosk browser —
# see README.md). Nothing here carries over from the pre-restructure
# mochaPot build (jellyfin/immich/vikunja/n8n/freshrss/mealie/
# actualbudget/stirlingpdf/roundcube/traefik all moved elsewhere or were
# cut — see infrastructure.md §4's "Deliberately not running").
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rand() { openssl rand -hex "${1:-32}"; }   # hex, never base64 -- see
  # infrastructure.md §6 "Secret generation".
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

ensure_file() {
  [[ -f "$1" ]] || { touch "$1"; }
  chmod 600 "$1"
}

set_if_absent() {
  local file="$1" key="$2" value="$3"
  ensure_file "$file"
  grep -qE "^${key}=" "$file" && return 0
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

get_value() {
  local file="$1" key="$2" line=""
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" 2>/dev/null || true)"
  [[ -z "$line" ]] && return 0
  printf '%s\n' "$line" | tail -n1 | cut -d= -f2-
}

prompt_if_placeholder() {
  # prompt_if_placeholder <file> <KEY> <prompt text> <placeholder> [--secret]
  local file="$1" key="$2" prompt_text="$3" placeholder="$4" secret="${5:-}"
  ensure_file "$file"

  local current
  current="$(get_value "$file" "$key")"
  [[ -n "$current" && "$current" != "$placeholder" ]] && return 0

  if [[ ! -t 0 ]]; then
    [[ -z "$current" ]] && printf '%s=%s\n' "$key" "$placeholder" >> "$file"
    return 0
  fi

  local value
  if [[ "$secret" == "--secret" ]]; then
    read -r -s -p "$prompt_text: " value
    printf '\n'
  else
    read -r -p "$prompt_text: " value
  fi

  if [[ -z "$value" ]]; then
    value="$placeholder"
    echo "  (left blank — keeping the placeholder; re-run this script once you have it)"
  fi

  grep -qE "^${key}=" "$file" 2>/dev/null && sed -i "/^${key}=/d" "$file"
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

# --- Per-app secrets go here ------------------------------------------

log "homeassistant/secrets.env.local"
# Recorder database -- HA itself doesn't create this database (see
# homeassistant/docker-compose.yml's own comment), only the credentials
# postgres-homeassistant will use to create it on first boot.
set_if_absent "${DIR}/homeassistant/secrets.env.local" "HA_DB_USERNAME" "homeassistant"
set_if_absent "${DIR}/homeassistant/secrets.env.local" "HA_DB_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/homeassistant/secrets.env.local" "HA_DB_DATABASE_NAME" "homeassistant"

log "pihole/secrets.env.local"
# Unlike sieve's primary Pi-hole (whose web password is deliberately
# disabled in favor of Authelia's ForwardAuth ALONE -- see
# stacks/sieve/pihole/secrets.env.local.example's own comment), this
# instance keeps its own web password ON and real even after gaining a
# Traefik/ForwardAuth route of its own (see ../traefik/) -- it's the
# deliberate native-login backdoor for when percolator's Authelia (or
# Traefik itself) is down. See README "Traefik and the native-login
# backdoor".
set_if_absent "${DIR}/pihole/secrets.env.local" "PIHOLE_WEBPASSWORD" "$(rand 16)"

# musicassistant -- no secrets.env.local: no auth config exists at the
# compose level (confirmed on the pre-restructure build, unchanged).
#
# kiosk -- host-native, not a container, no secrets.env.local. See
# kiosk/README.md.

log "traefik/secrets.env.local"
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" \
  "Cloudflare API token (Zone:DNS:Edit on \${DOMAIN}'s zone)" "REPLACE_ME_cf_token"

log "komodo-periphery/secrets.env.local"
# One-time bootstrap credential (CONFIRMED 2026-09-17 — see
# komodo-periphery/docker-compose.yml's own header comment): core.pub alone
# doesn't register this node as a Server in cellar's Komodo, only an
# onboarding key from cellar's Komodo UI does, on first connect. Pasted in,
# never randomly generated — leave REPLACE_ME once mochaPot shows up as a
# Server in Komodo's UI, it's not needed again after that.
prompt_if_placeholder "${DIR}/komodo-periphery/secrets.env.local" "PERIPHERY_ONBOARDING_KEY" \
  "Komodo onboarding key for 'mochaPot' (cellar's Komodo UI -> Settings -> Servers/onboarding)" \
  "REPLACE_ME" --secret

# --- Future apps go here ------------------------------------------------
#
#   set_if_absent "${DIR}/somesvc/secrets.env.local" "SOME_PASSWORD" "$(rand 16)"
# --------------------------------------------------------------------------

chmod 600 "${DIR}"/*/secrets.env.local 2>/dev/null || true

log "Summary"
still_needed=()
for f in "${DIR}"/*/secrets.env.local; do
  [[ -f "$f" ]] || continue
  app="$(basename "$(dirname "$f")")"
  while IFS='=' read -r key value; do
    [[ "$value" == *REPLACE_ME* ]] && still_needed+=("${app}/secrets.env.local: ${key}")
  done < "$f"
done

if [[ ${#still_needed[@]} -eq 0 ]]; then
  echo "Done — every value is set. Run ./render-configs.sh next."
else
  echo "Done, but these still need a real value — re-run this script anytime"
  echo "you have them (or edit the file directly):"
  for item in "${still_needed[@]}"; do
    echo "  - $item"
  done
fi
