#!/usr/bin/env bash
#
# generate-secrets.sh — fills in every secret cellar's apps need, at
# runtime, on the node itself. Same mechanics as every other node's copy:
# random values generated locally, written straight into each app's
# secrets.env.local, never committed to git (covered by this stack's
# .gitignore). Only the per-app section below differs per node.
#
# Rebuilt from scratch 2026-09-16 for cellar's post-restructure app list
# (restic, Samba/NFS, Scrutiny hub, Diun, Komodo Core + Mongo — see
# README.md). Nothing here carries over from the pre-restructure cellar:
# that build's vaultwarden/caddy secrets are gone because those apps moved
# to percolator, not because anything here failed.
#
# Usage: run directly on cellar itself.
#   ./generate-secrets.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rand() { openssl rand -hex "${1:-32}"; }   # hex, never base64 -- see
  # infrastructure.md §6 "Secret generation": base64's +/= characters break
  # OAuth2 client_secret_basic URL-encoding in some libraries (the
  # 2026-09-10 Mealie root cause). Komodo's webhook/JWT secrets and the
  # rest below don't go through that exact code path today, but there's no
  # reason to keep two secret-generation conventions in the fleet when one
  # is strictly safer.
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

ensure_file() {
  [[ -f "$1" ]] || { touch "$1"; }
  chmod 600 "$1"
}

set_if_absent() {
  # set_if_absent <file> <KEY> <value>
  local file="$1" key="$2" value="$3"
  ensure_file "$file"
  grep -qE "^${key}=" "$file" && return 0
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

get_value() {
  # get_value <file> <KEY> — prints the current value, empty if absent.
  local file="$1" key="$2" line=""
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" 2>/dev/null || true)"
  [[ -z "$line" ]] && return 0
  printf '%s\n' "$line" | tail -n1 | cut -d= -f2-
}

prompt_if_placeholder() {
  # prompt_if_placeholder <file> <KEY> <prompt text> <placeholder> [--secret]
  # Prompts only when the key is missing or still equals <placeholder>. A
  # real value (generated, hand-edited, or previously typed in) is left
  # alone. Blank input keeps the placeholder rather than writing an empty
  # value, so a later re-run asks again instead of quietly staying blank.
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

log "smb/secrets.env.local"
set_if_absent "${DIR}/smb/secrets.env.local" "SMB_BARISTA_PASSWORD" "$(rand 16)"

log "komodo/secrets.env.local"
# Five secrets, proportional to what Komodo actually holds on this node:
# once its own local Periphery agent is up (see komodo/docker-compose.yml),
# it's root-equivalent for cellar's own Docker socket, and it's the Core
# every other node's future Periphery agent will trust too. No insecure
# placeholder defaults used (the official reference file ships
# admin/admin, a_random_secret, a_random_jwt_secret, changeme -- none of
# those are used here).
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_DATABASE_USERNAME" "komodo"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_DATABASE_PASSWORD" "$(rand 32)"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_JWT_SECRET" "$(rand 32)"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_WEBHOOK_SECRET" "$(rand 32)"
set_if_absent "${DIR}/komodo/secrets.env.local" "KOMODO_INIT_ADMIN_PASSWORD" "$(rand 16)"
# No KOMODO_OIDC_CLIENT_SECRET here yet -- unlike the pre-restructure
# silo/komodo, this node has no Authelia to log in against (Authelia lives
# on percolator now, per infrastructure.md §4, and percolator hasn't been
# migrated into this repo yet). KOMODO_OIDC_ENABLED stays "false" in
# komodo/docker-compose.yml until that exists -- see README "Known gaps".

log "restic/secrets.env.local"
# The repository passphrase -- infrastructure.md §7 is explicit that this
# must survive the disaster that triggers the restore, i.e. it has to
# leave this node: after generating it, copy the value onto `flask` (see
# infrastructure.md §8) by hand. generate-secrets.sh only ever prints it
# once, right after creating it, for exactly this reason -- see the
# Summary section below.
set_if_absent "${DIR}/restic/secrets.env.local" "RESTIC_PASSWORD" "$(rand 32)"
# rclone's Google Drive remote needs its OWN API client, not the shared
# default -- infrastructure.md §7: "rclone's shared default is the single
# biggest cause of 403 userRateLimitExceeded." Create one at
# console.cloud.google.com (a project with the Drive API enabled, an OAuth
# client of type "Desktop app"), then paste its ID/secret here. Can't be
# generated locally -- prompted, same category as the Cloudflare tokens
# elsewhere in this fleet.
prompt_if_placeholder "${DIR}/restic/secrets.env.local" "RCLONE_DRIVE_CLIENT_ID" \
  "rclone Google Drive OAuth client ID (console.cloud.google.com, your own project)" "REPLACE_ME_drive_client_id"
prompt_if_placeholder "${DIR}/restic/secrets.env.local" "RCLONE_DRIVE_CLIENT_SECRET" \
  "rclone Google Drive OAuth client secret" "REPLACE_ME_drive_client_secret" --secret

# scrutiny, diun -- no secrets needed. Scrutiny (as the hub, running here
# for the first time) has no auth of its own to protect -- see README
# "Known gaps", same zero-auth reality the pre-restructure silo build
# already found and accepted for the LAN. Diun has no web UI or API
# surface whatsoever, so there's nothing to log into either.

# nfs -- host-native (see nfs/README section), not a container, has no
# secrets.env.local -- same reasoning as every host-native piece of this
# fleet (SSH keys, not password auth).

log "traefik/secrets.env.local"
# Real external Cloudflare credential -- can't be randomly generated, same
# category and same required scope (Zone:DNS:Edit on ${DOMAIN}'s zone) as
# every other node's Traefik/Caddy instance in this fleet. Safe to reuse
# the exact same real token value across all of them if it already has
# that scope -- Cloudflare tokens aren't tied to one server, only to a
# zone and a permission set.
prompt_if_placeholder "${DIR}/traefik/secrets.env.local" "CF_DNS_API_TOKEN" \
  "Cloudflare API token (Zone:DNS:Edit on \${DOMAIN}'s zone)" "REPLACE_ME_cf_token"

# --- Future apps go here ------------------------------------------------
#
#   set_if_absent "${DIR}/somesvc/secrets.env.local" "SOME_PASSWORD" "$(rand 16)"
#
# For a value that can't be randomly generated (an API token, etc.):
#
#   prompt_if_placeholder "${DIR}/somesvc/secrets.env.local" "SOME_API_TOKEN" \
#     "Some service API token" "REPLACE_ME_some_api_token" --secret
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
  echo
  echo "See stacks/cellar/README.md for where each one comes from."
fi

echo
echo "Reminder: restic/secrets.env.local's RESTIC_PASSWORD has not been"
echo "copied anywhere else. Add it to flask (infrastructure.md §8) before"
echo "you rely on this repository for anything -- an encrypted backup whose"
echo "only key lives on the machine that might die with it is not a backup."
