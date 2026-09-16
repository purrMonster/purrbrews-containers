#!/usr/bin/env bash
#
# setup-secrets.sh — master first-time-setup script. One command instead of
# a sequence to remember and get half-right. Same mechanics as every other
# node's setup-secrets.sh.
#
# Does, in order:
#   1. Creates .env.local from local.env.example if it doesn't exist yet.
#   2. Prompts for any REPLACE_ME value still in .env.local — generic scan,
#      not a hardcoded list of variable names, so a future addition to
#      local.env.example gets picked up automatically without touching
#      this script.
#   3. Runs ./generate-secrets.sh — generates every secret cellar's apps
#      need, locally, right here on cellar, straight into each app's own
#      secrets.env.local.
#   4. Checks the results of step 3 for any lingering REPLACE_ME and warns
#      if found (an external credential generate-secrets.sh can't make up
#      on its own — e.g. the rclone Google Drive client secret).
#   5. Runs ./render-configs.sh so every template picks up whatever changed
#      in steps 1-4.
#
# Idempotent throughout — safe to re-run any time. Only ever fills a
# REPLACE_ME that's still actually REPLACE_ME; a value already set, by hand
# or via a previous run, is never touched.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

log ".env.local"

if [[ ! -f "${DIR}/.env.local" ]]; then
  [[ -f "${DIR}/local.env.example" ]] || fail "local.env.example not found in ${DIR} — can't create .env.local from it."
  cp "${DIR}/local.env.example" "${DIR}/.env.local"
  echo "  created .env.local from local.env.example"
else
  # A first run being already done does NOT mean nothing is left to ask —
  # a later git pull can add a new required key (e.g. a new app's LAN_IP
  # or a cross-node secret like a Komodo Periphery connection value) to
  # local.env.example, and without this, an existing .env.local from a
  # completed prior run would never pick it up: the REPLACE_ME scan below
  # only sees keys that are ALREADY in the file. Bug fixed 2026-09-16 —
  # same key-sync step sieve's and percolator's setup-secrets.sh already
  # had; cellar/mochaPot/grinder/roastery were missing it.
  added=0
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    if ! grep -qE "^${BASH_REMATCH[1]}=" "${DIR}/.env.local"; then
      printf '%s\n' "$line" >> "${DIR}/.env.local"
      echo "  added new key ${BASH_REMATCH[1]} (re-run to fill it in if it's REPLACE_ME)"
      added=1
    fi
  done < "${DIR}/local.env.example"
  [[ "$added" -eq 1 ]] || echo "  up to date with local.env.example"
fi
chmod 600 "${DIR}/.env.local"

# Generic REPLACE_ME scan — matches any KEY=value line where the value
# contains REPLACE_ME anywhere in it. Prompts once per matching key; a
# blank answer keeps the placeholder so a later re-run asks again instead
# of silently staying wrong.
fill_replace_me() {
  local file="$1" tmpfile changed=0
  tmpfile="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*REPLACE_ME.*)$ ]]; then
      local key="${BASH_REMATCH[1]}" placeholder="${BASH_REMATCH[2]}"
      if [[ -t 0 ]]; then
        local value
        read -r -p "  ${key} (currently '${placeholder}'): " value
        if [[ -n "$value" ]]; then
          echo "${key}=${value}" >> "$tmpfile"
          changed=1
        else
          echo "  (left blank — keeping placeholder; re-run this script once you have it)"
          echo "$line" >> "$tmpfile"
        fi
      else
        # Not an interactive terminal (piped/unattended) — leave it, don't hang.
        echo "$line" >> "$tmpfile"
      fi
    else
      echo "$line" >> "$tmpfile"
    fi
  done < "$file"
  mv "$tmpfile" "$file"
  chmod 600 "$file"
  [[ "$changed" -eq 1 ]] && echo "  updated $(basename "$file")"
  return 0
}

fill_replace_me "${DIR}/.env.local"

still_replace_me="$(grep -l 'REPLACE_ME' "${DIR}/.env.local" 2>/dev/null || true)"
if [[ -n "$still_replace_me" ]]; then
  echo "  still has a REPLACE_ME value — re-run this script once you have it, or edit .env.local directly"
fi

log "Generating secrets (./generate-secrets.sh)"
"${DIR}/generate-secrets.sh"

log "Checking generated secrets for lingering REPLACE_ME values"
found_placeholder=0
shopt -s nullglob
for f in "${DIR}"/*/secrets.env.local; do
  if grep -q 'REPLACE_ME' "$f" 2>/dev/null; then
    found_placeholder=1
    app="$(basename "$(dirname "$f")")"
    echo "  WARNING: ${app}/secrets.env.local still has a REPLACE_ME value."
    echo "           Re-run ./generate-secrets.sh once you have it (it'll prompt again)."
  fi
done
shopt -u nullglob
[[ "$found_placeholder" -eq 0 ]] && echo "  none found"

log "Rendering configs (./render-configs.sh)"
"${DIR}/render-configs.sh"

log "Done."
