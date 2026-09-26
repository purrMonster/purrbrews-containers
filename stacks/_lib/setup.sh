#!/usr/bin/env bash
#
# setup.sh: first-time setup for a node, and the thing to re-run after any
# pull that adds a setting or an app. Every node's ./setup-secrets.sh calls
# this with its own directory. Safe to run as often as you like; a value that
# is already set is never changed.
#
#   1. .env.local: created from local.env.example; keys added to the example
#      later are appended; renamed keys are copied to their new names
#   2. asks for anything in .env.local that's still REPLACE_ME
#   3. fills in LAN_INTERFACE from the default route, if the node has that key
#   4. every app's secrets, from <app>/secrets.conf (see secrets.sh)
#   5. ./render-configs.sh
#
# Run as the ops user. It uses sudo itself for the bits that need it.
#
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=secrets.sh
source "$LIB/secrets.sh"

load_node "${1:?usage: setup.sh <node dir>}"
not_root
command -v openssl >/dev/null || die "openssl is required."
EXAMPLE="$NODE_DIR/local.env.example"

# ── 1. .env.local ────────────────────────────────────────────────────────────
log ".env.local"
if [[ ! -f "$ENV_LOCAL" ]]; then
  install -m 600 "$EXAMPLE" "$ENV_LOCAL"
  note "created from local.env.example"
else
  chmod 600 "$ENV_LOCAL"
  # Renames first, or the example's new key would land as REPLACE_ME and
  # hide the old value.
  migrate_renamed_keys
  added=0
  while IFS= read -r line; do
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    if ! env_has "$ENV_LOCAL" "${BASH_REMATCH[1]}"; then
      [[ -z "$(tail -c1 "$ENV_LOCAL")" ]] || printf '\n' >> "$ENV_LOCAL"
      printf '%s\n' "$line" >> "$ENV_LOCAL"
      note "added new key ${BASH_REMATCH[1]}"
      added=1
    fi
  done < "$EXAMPLE"
  [[ $added -eq 1 ]] || note "up to date with local.env.example"
fi

# An unquoted value with a space in it breaks the renderer, which sources this
# file with bash. Quote any such value in place (the value itself is unchanged).
while IFS= read -r line; do
  [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=([^\'\"].*[[:space:]].*)$ ]] || continue
  env_put "$ENV_LOCAL" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  note "quoted ${BASH_REMATCH[1]}, which has spaces in it"
done < <(cat "$ENV_LOCAL")

# ── 2. Settings still REPLACE_ME ─────────────────────────────────────────────
log "Settings to fill in"
mapfile -t todo < <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$ENV_LOCAL" | cut -d= -f1)
for key in "${todo[@]}"; do
  value=''
  [[ -t 0 ]] && read -r -p "  $key (now '$(env_get "$ENV_LOCAL" "$key")'): " value
  if [[ -n "$value" ]]; then
    env_put "$ENV_LOCAL" "$key" "$value"
  else
    note "$key still needs a value"
  fi
done
[[ ${#todo[@]} -gt 0 ]] || note "none"

# ── 3. Things the node can work out itself ───────────────────────────────────
if env_has "$ENV_LOCAL" LAN_INTERFACE && [[ -z "$(env_get "$ENV_LOCAL" LAN_INTERFACE)" ]]; then
  iface="$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}')"
  [[ -n "$iface" ]] || die "no default route, so I can't guess LAN_INTERFACE; set it in .env.local."
  env_put "$ENV_LOCAL" LAN_INTERFACE "$iface"
  note "LAN_INTERFACE=$iface (from the default route)"
fi

# ── 4. Secrets ───────────────────────────────────────────────────────────────
log "Secrets"
use_docker
generate_secrets

# ── 5. Render ────────────────────────────────────────────────────────────────
log "Rendering configs"
render_ok=1
bash "$LIB/render-configs.sh" "$NODE_DIR" || render_ok=0

# ── Summary ──────────────────────────────────────────────────────────────────
log "Summary"
pending=()
while IFS= read -r key; do pending+=(".env.local: $key"); done \
  < <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$ENV_LOCAL" | cut -d= -f1)
for f in "$NODE_DIR"/*/secrets.env.local; do
  [[ -f "$f" ]] || continue
  while IFS= read -r key; do pending+=("${f#"$NODE_DIR"/}: $key"); done \
    < <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$f" | cut -d= -f1)
done

for n in "${SECRETS_NOTES[@]}"; do note "$n"; done
if [[ ${#pending[@]} -gt 0 ]]; then
  echo "Still needs a real value (run ./setup-secrets.sh again once you have it):"
  printf '  - %s\n' "${pending[@]}"
fi
[[ $SECRETS_FAILED -eq 0 ]] || echo "Some hashes couldn't be made; run this again once Docker works."
[[ $render_ok -eq 1 ]] || echo "Rendering failed (see above); nothing that was already rendered was touched."

if [[ ${#pending[@]} -eq 0 && $SECRETS_FAILED -eq 0 && $render_ok -eq 1 ]]; then
  echo "All set. Next: sudo ./firewall.sh, then ./compose.sh <app> up -d in the README's order."
else
  exit 1
fi
