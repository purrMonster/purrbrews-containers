#!/usr/bin/env bash
#
# setup-secrets.sh — first-time-setup script. Same mechanics as every other
# node's setup-secrets.sh, minus the generate-secrets.sh step: immich-ml has
# no API key, no password, nothing to generate. If a future app here (Ollama,
# Jellyfin) ever needs one, add a generate-secrets.sh and call it here, same
# as every other node.
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
fi
chmod 600 "${DIR}/.env.local"

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

log "Rendering configs (./render-configs.sh)"
"${DIR}/render-configs.sh"

log "Done."
echo "Next: verify GPU passthrough, then ./compose.sh immich-ml up -d — see README.md."
