#!/usr/bin/env bash
#
# generate-secrets.sh — create every secret percolator's apps need, on this
# node, into each app's gitignored <app>/secrets.env.local (mode 600).
#
# Idempotent: a key that already has a real value is never touched. To rotate
# a secret, delete its line(s) and re-run (for an OIDC client, delete both
# <APP>_OIDC_CLIENT_SECRET in the app's file and <APP>_OIDC_CLIENT_SECRET_HASH
# in authelia's), then render and recreate the affected containers.
#
# Rules this script follows:
#   - Random values are hex (openssl rand -hex). base64's + / = break OIDC
#     client_secret_basic in clients that don't URL-encode the secret.
#   - Values containing '$' (hashes) are written single-quoted so neither bash
#     `source` nor docker compose's env-file parser expands them.
#   - Run as barista, never under sudo (that leaves root-owned files that break
#     the next render). Only the hashing `docker run` uses sudo.
#   - Authelia and every OIDC app share this node, so each app's plaintext
#     client secret and Authelia's hash of it are written in the same run.
#
# shellcheck disable=SC2016,SC2094  # literal $ in regexes; summary loop only reads
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTHELIA_IMAGE="authelia/authelia:4.39.27"   # keep in step with authelia/docker-compose.yml

[[ $EUID -ne 0 ]] || { echo "Don't run this under sudo — see the header." >&2; exit 1; }
umask 077

rand() { openssl rand -hex "${1:-32}"; }
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

DOCKER=(docker)
docker info >/dev/null 2>&1 || DOCKER=(sudo docker)

ensure_file() { [[ -f "$1" ]] || : > "$1"; chmod 600 "$1"; }

get_value() {
  local line
  line="$(grep -E "^$2=" "$1" 2>/dev/null | tail -n1 || true)"
  line="${line#*=}"; line="${line#\'}"; line="${line%\'}"
  printf '%s' "$line"
}

# set_if_absent <file> <KEY> <value> [--quote]
set_if_absent() {
  local file="$1" key="$2" value="$3" quote="${4:-}"
  ensure_file "$file"
  grep -qE "^${key}=" "$file" && return 0
  if [[ "$quote" == --quote ]]; then
    printf "%s='%s'\n" "$key" "$value" >> "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# prompt_if_placeholder <file> <KEY> <prompt> — asks (silently) when the key
# is missing or still a placeholder. Blank input or no terminal keeps a
# REPLACE_ME placeholder, so compose.sh refuses to start the app until set.
prompt_if_placeholder() {
  local file="$1" key="$2" prompt="$3" current value
  ensure_file "$file"
  current="$(get_value "$file" "$key")"
  [[ -n "$current" && "$current" != *REPLACE_ME* ]] && return 0
  value=""
  if [[ -t 0 ]]; then
    read -r -s -p "  ${prompt}: " value; printf '\n'
  fi
  [[ -n "$value" ]] || value="REPLACE_ME"
  sed -i "/^${key}=/d" "$file"
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

# authelia_hash <pbkdf2|argon2> <plaintext> — prints the PHC digest or nothing.
authelia_hash() {
  "${DOCKER[@]}" run --rm "$AUTHELIA_IMAGE" \
    authelia crypto hash generate "$1" --password "$2" 2>/dev/null \
    | grep -oE '\$(pbkdf2-sha512|argon2id)\$[^[:space:]]+' | head -n1 || true
}

# set_hash <file> <KEY> <plaintext> <pbkdf2|argon2>
set_hash() {
  local file="$1" key="$2" plain="$3" alg="$4" digest
  ensure_file "$file"
  [[ -n "$(get_value "$file" "$key")" ]] && return 0
  digest="$(authelia_hash "$alg" "$plain")"
  if [[ -z "$digest" ]]; then
    echo "  ! could not hash ${key} (is Docker running? can it pull ${AUTHELIA_IMAGE}?) — re-run later" >&2
    HASH_FAILED=1
    return 0
  fi
  printf "%s='%s'\n" "$key" "$digest" >> "$file"
}

HASH_FAILED=0
AUTHELIA="${DIR}/authelia/secrets.env.local"

# oidc_client <app-dir> <PREFIX> — plaintext into the app, hash into Authelia.
oidc_client() {
  local app_file="${DIR}/$1/secrets.env.local" prefix="$2" plain
  set_if_absent "$app_file" "${prefix}_OIDC_CLIENT_SECRET" "$(rand 32)"
  plain="$(get_value "$app_file" "${prefix}_OIDC_CLIENT_SECRET")"
  set_hash "$AUTHELIA" "${prefix}_OIDC_CLIENT_SECRET_HASH" "$plain" pbkdf2
}

# ── traefik + crowdsec ──────────────────────────────────────────────────────
log "crowdsec"
set_if_absent "${DIR}/crowdsec/secrets.env.local" CROWDSEC_BOUNCER_KEY "$(rand 32)"

log "traefik"
set_if_absent "${DIR}/traefik/secrets.env.local" CROWDSEC_BOUNCER_KEY \
  "$(get_value "${DIR}/crowdsec/secrets.env.local" CROWDSEC_BOUNCER_KEY)"
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" CF_DNS_API_TOKEN \
  "Cloudflare API token (Zone → DNS → Edit, this zone only)"

# ── identity ────────────────────────────────────────────────────────────────
log "lldap"
set_if_absent "${DIR}/lldap/secrets.env.local" LLDAP_ADMIN_PASSWORD "$(rand 24)"
set_if_absent "${DIR}/lldap/secrets.env.local" LLDAP_JWT_SECRET "$(rand 32)"
set_if_absent "${DIR}/lldap/secrets.env.local" LLDAP_KEY_SEED "$(rand 32)"

log "authelia"
set_if_absent "$AUTHELIA" AUTHELIA_LDAP_PASSWORD \
  "$(get_value "${DIR}/lldap/secrets.env.local" LLDAP_ADMIN_PASSWORD)"
set_if_absent "$AUTHELIA" AUTHELIA_SESSION_SECRET "$(rand 32)"
set_if_absent "$AUTHELIA" AUTHELIA_STORAGE_ENCRYPTION_KEY "$(rand 32)"
set_if_absent "$AUTHELIA" AUTHELIA_RESET_PASSWORD_JWT_SECRET "$(rand 32)"
set_if_absent "$AUTHELIA" AUTHELIA_OIDC_HMAC_SECRET "$(rand 32)"
set_if_absent "$AUTHELIA" AUTHELIA_REDIS_PASSWORD "$(rand 32)"
if [[ -z "$(get_value "$AUTHELIA" AUTHELIA_OIDC_JWK_PRIVATE_KEY)" ]]; then
  # One line with literal \n: envsubst knows nothing about YAML indentation,
  # so the key goes into a double-quoted YAML string that un-escapes it.
  jwk="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null | sed ':a;N;$!ba;s/\n/\\n/g')"
  [[ "$jwk" == -----BEGIN* ]] || { echo "openssl genpkey failed" >&2; exit 1; }
  set_if_absent "$AUTHELIA" AUTHELIA_OIDC_JWK_PRIVATE_KEY "$jwk" --quote
  unset jwk
fi

# ── apps ────────────────────────────────────────────────────────────────────
log "vaultwarden"
VW="${DIR}/vaultwarden/secrets.env.local"
set_if_absent "$VW" VAULTWARDEN_ADMIN_PASSWORD "$(rand 24)"
set_hash "$VW" VAULTWARDEN_ADMIN_TOKEN "$(get_value "$VW" VAULTWARDEN_ADMIN_PASSWORD)" argon2
oidc_client vaultwarden VAULTWARDEN

log "nextcloud"
set_if_absent "${DIR}/nextcloud/secrets.env.local" NEXTCLOUD_ADMIN_PASSWORD "$(rand 24)"
set_if_absent "${DIR}/nextcloud/secrets.env.local" NEXTCLOUD_DB_PASSWORD "$(rand 32)"
oidc_client nextcloud NEXTCLOUD

log "immich"
set_if_absent "${DIR}/immich/secrets.env.local" IMMICH_DB_PASSWORD "$(rand 32)"
oidc_client immich IMMICH

log "paperless"
set_if_absent "${DIR}/paperless/secrets.env.local" PAPERLESS_ADMIN_PASSWORD "$(rand 24)"
set_if_absent "${DIR}/paperless/secrets.env.local" PAPERLESS_SECRET_KEY "$(rand 32)"
set_if_absent "${DIR}/paperless/secrets.env.local" PAPERLESS_DB_PASSWORD "$(rand 32)"
oidc_client paperless PAPERLESS

log "mealie"
oidc_client mealie MEALIE

log "vikunja"
set_if_absent "${DIR}/vikunja/secrets.env.local" VIKUNJA_SERVICE_SECRET "$(rand 32)"
oidc_client vikunja VIKUNJA

log "actualbudget"
oidc_client actualbudget ACTUALBUDGET

log "homeassistant (OIDC client only -- the app itself lives on mochaPot)"
# Every other oidc_client() call assumes the app's own secrets.env.local is a
# sibling directory here, which isn't true for Home Assistant since it moved
# to mochaPot in the 2026-09-15 restructure. Authelia only ever needs the
# HASH (below, read by configuration.yml.template), so the plaintext is
# generated and kept here purely as the one authoritative place to retrieve
# it from -- hass-oidc-auth reads it from Home Assistant's own
# configuration.yaml/secrets.yaml on mochaPot, not from any env var, so there
# is no automated way to deliver it there; copy it over by hand:
#   grep '^HOMEASSISTANT_OIDC_CLIENT_SECRET=' authelia/secrets.env.local
set_if_absent "$AUTHELIA" HOMEASSISTANT_OIDC_CLIENT_SECRET "$(rand 32)"
set_hash "$AUTHELIA" HOMEASSISTANT_OIDC_CLIENT_SECRET_HASH \
  "$(get_value "$AUTHELIA" HOMEASSISTANT_OIDC_CLIENT_SECRET)" pbkdf2

log "freshrss"
set_if_absent "${DIR}/freshrss/secrets.env.local" FRESHRSS_OIDC_CRYPTO_KEY "$(rand 32)"
oidc_client freshrss FRESHRSS

# ── summary ─────────────────────────────────────────────────────────────────
chmod 600 "${DIR}"/*/secrets.env.local 2>/dev/null || true

log "Summary"
pending=()
for f in "${DIR}"/*/secrets.env.local; do
  while IFS='=' read -r key value; do
    [[ "$value" == *REPLACE_ME* ]] && pending+=("$(basename "$(dirname "$f")")/secrets.env.local: ${key}")
  done < "$f"
done
if [[ ${#pending[@]} -gt 0 ]]; then
  echo "Still needs a real value (re-run once you have it):"
  printf '  - %s\n' "${pending[@]}"
fi
if [[ "$HASH_FAILED" -eq 1 ]]; then
  echo "Some hashes could not be generated — re-run once Docker works." >&2
  exit 1
fi
[[ ${#pending[@]} -eq 0 ]] && echo "All secrets present. Next: ./render-configs.sh"
exit 0
