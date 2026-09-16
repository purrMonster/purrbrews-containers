#!/usr/bin/env bash
#
# setup-secrets.sh — one command for first-time setup, safe to re-run.
#
#   1. Creates .env.local from local.env.example, or appends keys that were
#      added to the example since .env.local was created.
#   2. Asks for every REPLACE_ME value in .env.local.
#   3. Runs ./generate-secrets.sh.
#   4. Runs ./render-configs.sh.
#
# A value you have already set is never changed. Run as barista, not sudo.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LOCAL="${DIR}/.env.local"
EXAMPLE="${DIR}/local.env.example"

[[ $EUID -ne 0 ]] || { echo "Don't run this under sudo." >&2; exit 1; }
log() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

log ".env.local"
umask 077
if [[ ! -f "$ENV_LOCAL" ]]; then
  cp "$EXAMPLE" "$ENV_LOCAL"
  echo "  created from local.env.example"
else
  added=0
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    if ! grep -qE "^${BASH_REMATCH[1]}=" "$ENV_LOCAL"; then
      printf '%s\n' "$line" >> "$ENV_LOCAL"
      echo "  added new key ${BASH_REMATCH[1]}"
      added=1
    fi
  done < "$EXAMPLE"
  [[ "$added" -eq 1 ]] || echo "  up to date with local.env.example"
fi
chmod 600 "$ENV_LOCAL"

interactive=0; [[ -t 0 ]] && interactive=1
tmp="$(mktemp)"
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*REPLACE_ME.*)$ && $interactive -eq 1 ]]; then
    key="${BASH_REMATCH[1]}"
    read -r -p "  ${key} [${BASH_REMATCH[2]}]: " value < /dev/tty
    if [[ -n "$value" ]]; then
      line="${key}=${value}"
    else
      echo "  (kept the placeholder — apps that need it won't start until it is set)"
    fi
  fi
  printf '%s\n' "$line" >> "$tmp"
done < "$ENV_LOCAL"
cmp -s "$tmp" "$ENV_LOCAL" || cat "$tmp" > "$ENV_LOCAL"
rm -f "$tmp"

if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$ENV_LOCAL"; then
  echo "  still has placeholders: $(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$ENV_LOCAL" | cut -d= -f1 | tr '\n' ' ')"
fi

log "Generating secrets"
"${DIR}/generate-secrets.sh"

log "Rendering configs"
"${DIR}/render-configs.sh"
