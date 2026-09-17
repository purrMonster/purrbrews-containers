#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret grinder's apps need, at
# runtime, on the node itself. Same mechanics as every other node's copy.
#
# grinder is entirely new to this fleet (see local.env.example's own
# header) -- nothing here migrates from anywhere.
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

log "n8n/secrets.env.local"
# Pinned, not left to auto-generate -- losing this key makes every stored
# credential unreadable (see n8n/docker-compose.yml's own comment). Copy
# it to flask (infrastructure.md §8) once generated -- it's in that file's
# emergency-kit list for exactly this reason.
set_if_absent "${DIR}/n8n/secrets.env.local" "N8N_ENCRYPTION_KEY" "$(rand 32)"

log "postgres-vector/secrets.env.local"
set_if_absent "${DIR}/postgres-vector/secrets.env.local" "PGVECTOR_USERNAME" "pgvector"
set_if_absent "${DIR}/postgres-vector/secrets.env.local" "PGVECTOR_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/postgres-vector/secrets.env.local" "PGVECTOR_DATABASE_NAME" "pgvector"

log "karakeep/secrets.env.local"
set_if_absent "${DIR}/karakeep/secrets.env.local" "KARAKEEP_MEILI_MASTER_KEY" "$(rand 32)"
set_if_absent "${DIR}/karakeep/secrets.env.local" "KARAKEEP_NEXTAUTH_SECRET" "$(rand 32)"

log "fittrackee/secrets.env.local"
set_if_absent "${DIR}/fittrackee/secrets.env.local" "FITTRACKEE_SECRET_KEY" "$(rand 32)"
set_if_absent "${DIR}/fittrackee/secrets.env.local" "FITTRACKEE_DB_USERNAME" "fittrackee"
set_if_absent "${DIR}/fittrackee/secrets.env.local" "FITTRACKEE_DB_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/fittrackee/secrets.env.local" "FITTRACKEE_DB_DATABASE_NAME" "fittrackee"

log "esphome/secrets.env.local"
set_if_absent "${DIR}/esphome/secrets.env.local" "ESPHOME_DASHBOARD_PASSWORD" "$(rand 16)"

log "speedtest-tracker/secrets.env.local"
set_if_absent "${DIR}/speedtest-tracker/secrets.env.local" "SPEEDTEST_TRACKER_APP_KEY" "base64:$(rand 32)"
set_if_absent "${DIR}/speedtest-tracker/secrets.env.local" "SPEEDTEST_TRACKER_ADMIN_PASSWORD" "$(rand 16)"

# openwebui -- no secrets.env.local: WEBUI_AUTH's account is created
# through its own onboarding UI, nothing to generate ahead of time.
#
# embedding-worker -- no secrets.env.local: no auth surface, reachable
# only from grinder_net.
#
# traccar -- no secrets.env.local: default admin/admin is a first-login
# manual change, not something compose/env can set for this image (see
# traccar/docker-compose.yml's own comment).

log "traefik/secrets.env.local"
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" \
  "Cloudflare API token (Zone:DNS:Edit on \${DOMAIN}'s zone)" "REPLACE_ME_cf_token"

log "komodo-periphery/secrets.env.local"
# One-time bootstrap credential (CONFIRMED 2026-09-17 — see
# komodo-periphery/docker-compose.yml's own header comment): core.pub alone
# doesn't register this node as a Server in cellar's Komodo, only an
# onboarding key from cellar's Komodo UI does, on first connect. Pasted in,
# never randomly generated — leave REPLACE_ME once grinder shows up as a
# Server in Komodo's UI, it's not needed again after that.
prompt_if_placeholder "${DIR}/komodo-periphery/secrets.env.local" "PERIPHERY_ONBOARDING_KEY" \
  "Komodo onboarding key for 'grinder' (cellar's Komodo UI -> Settings -> Servers/onboarding)" \
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

echo
echo "Reminder: n8n/secrets.env.local's N8N_ENCRYPTION_KEY has not been"
echo "copied anywhere else. Add it to flask (infrastructure.md §8) --"
echo "losing it invalidates every credential stored in every n8n workflow."
