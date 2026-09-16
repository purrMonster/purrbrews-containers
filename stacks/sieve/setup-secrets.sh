#!/usr/bin/env bash
#
# setup-secrets.sh — one command to prepare sieve's stacks. Safe to re-run.
#
#   1. .env.local: created from local.env.example; keys added to the example
#      later are appended, existing values are never touched.
#   2. Asks for anything still REPLACE_ME (the domain).
#   3. Fills in what the node already knows: LAN_INTERFACE (default route);
#      Pi-hole's static leases and host names from the fleet list
#      (init/purrbrews-mac.sh) plus your PIHOLE_*_EXTRA_HOSTS; and a DNS record
#      for every Traefik router in the repo, pointing at its node: file-provider
#      routes (stacks/*/traefik/dynamic/*.yml, stacks/*/traefik/config/*.template)
#      and container labels (stacks/*/*/docker-compose.yml).
#   4. Creates the data directories under DATA_DIR.
#   5. Runs ./generate-secrets.sh.
#
# Run as barista (not sudo); it uses sudo for the few steps that need root.
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${DIR}/../.." && pwd)"
ENV_LOCAL="${DIR}/.env.local"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -ne 0 ]] || die "Run as your ops user, not root/sudo."

get() {  # get <file> <KEY>
  local line; [[ -f "$1" ]] || return 0
  line="$(grep -E "^$2=" "$1" | tail -n1 || true)"; line="${line#*=}"
  line="${line#\'}"; line="${line%\'}"; printf '%s' "$line"
}
set_env() {  # set_env <KEY> <value> — replace in place (keeps position/comments), or append
  local key="$1" value="$2" tmp
  tmp="$(mktemp "${ENV_LOCAL}.XXXX")"
  if grep -qE "^${key}=" "$ENV_LOCAL"; then
    KEY="$key" VAL="'${value}'" awk 'index($0, ENVIRON["KEY"]"=")==1 {print ENVIRON["KEY"]"="ENVIRON["VAL"]; next} {print}' "$ENV_LOCAL" > "$tmp"
  else
    cat "$ENV_LOCAL" > "$tmp"; printf "%s='%s'\n" "$key" "$value" >> "$tmp"
  fi
  chmod 600 "$tmp"; mv "$tmp" "$ENV_LOCAL"
}

# ── 1. .env.local ─────────────────────────────────────────────────────────────
log ".env.local"
if [[ ! -f "$ENV_LOCAL" ]]; then
  install -m 600 "${DIR}/local.env.example" "$ENV_LOCAL"
  echo "  created from local.env.example"
fi
chmod 600 "$ENV_LOCAL"
added=0
while IFS= read -r line; do
  [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]] || continue
  if ! grep -qE "^${BASH_REMATCH[1]}=" "$ENV_LOCAL"; then
    printf '%s\n' "$line" >> "$ENV_LOCAL"; echo "  added new key ${BASH_REMATCH[1]}"; added=1
  fi
done < "${DIR}/local.env.example"
[[ $added -eq 1 ]] || echo "  up to date with local.env.example"

# ── 2. Anything still REPLACE_ME ──────────────────────────────────────────────
log "Settings to fill in"
pending=0
mapfile -t todo < <(grep -E '^[A-Z_]+=.*REPLACE_ME' "$ENV_LOCAL" | cut -d= -f1)
for key in "${todo[@]}"; do
  if [[ -t 0 ]]; then
    read -r -p "  ${key} (now '$(get "$ENV_LOCAL" "$key")'): " value
    if [[ -n "$value" ]]; then set_env "$key" "$value"; continue; fi
  fi
  echo "  ${key} still needs a value"; pending=1
done
[[ $pending -eq 1 ]] || echo "  none"

# ── 3. Values the node can work out ───────────────────────────────────────────
log "Detected values"
if [[ -z "$(get "$ENV_LOCAL" LAN_INTERFACE)" ]]; then
  iface="$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  [[ -n "$iface" ]] || die "No default route — can't detect LAN_INTERFACE. Set it in .env.local."
  set_env LAN_INTERFACE "$iface"
fi
echo "  LAN_INTERFACE=$(get "$ENV_LOCAL" LAN_INTERFACE)"

MAC_TOOL="${PROJECT_DIR}/init/purrbrews-mac.sh"
[[ -f "$MAC_TOOL" ]] || die "$MAC_TOOL not found."
fleet_csv="$(sudo bash "$MAC_TOOL" list --format csv 2>/dev/null | tail -n +2)" \
  || die "purrbrews-mac.sh failed — check /etc/purrbrews/purrbrews-init.env."
[[ -n "$fleet_csv" ]] || die "purrbrews-mac.sh returned no nodes."

dhcp_hosts=(); dns_hosts=()
while IFS=, read -r name ip mac; do
  dhcp_hosts+=("${mac},${ip},${name}")
  dns_hosts+=("${ip} ${name}")
done <<< "$fleet_csv"
join() { local IFS=';'; printf '%s' "$*"; }
extra="$(get "$ENV_LOCAL" PIHOLE_DHCP_EXTRA_HOSTS)"; [[ -n "$extra" ]] && dhcp_hosts+=("$extra")
extra="$(get "$ENV_LOCAL" PIHOLE_DNS_EXTRA_HOSTS)";  [[ -n "$extra" ]] && dns_hosts+=("$extra")
set_env PIHOLE_DHCP_HOSTS "$(join "${dhcp_hosts[@]}")"
set_env PIHOLE_DNS_HOSTS  "$(join "${dns_hosts[@]}")"
echo "  Pi-hole: ${#dhcp_hosts[@]} static lease entr(ies), ${#dns_hosts[@]} host name entr(ies)"

# Every node's Traefik routers → a DNS record pointing at that node.
# router_labels <file>: the <label> of each router rule Host(`<label>.<domain>`),
# where <domain> is written {{ env "DOMAIN" }} (file provider, Go template) or
# ${DOMAIN} (rendered template, compose label). Only real rule lines count,
# `rule:` or `.rule=`, so examples in comments are ignored.
# shellcheck disable=SC2016  # literal backticks, braces and $ in the patterns
router_labels() {
  grep -E '^[[:space:]]*(rule:|-?[[:space:]]*traefik\.http\.routers\.[A-Za-z0-9_-]+\.rule=)' "$1" \
    | grep -oE 'Host\(`[a-z0-9-]+\.(\{\{ *env "DOMAIN" *\}\}|\$\{DOMAIN\})`\)' \
    | sed -E 's/^Host\(`([a-z0-9-]+)\..*/\1/' | sort -u || true
}
DOMAIN="$(get "$ENV_LOCAL" DOMAIN)"
declare -A node_ip=()
while IFS=, read -r name ip _; do node_ip[$name]="$ip"; done <<< "$fleet_csv"
dns_lines=()
if [[ -n "$DOMAIN" && "$DOMAIN" != *REPLACE_ME* ]]; then
  shopt -s nullglob
  for f in "${PROJECT_DIR}"/stacks/*/traefik/dynamic/*.yml \
           "${PROJECT_DIR}"/stacks/*/traefik/config/*.template \
           "${PROJECT_DIR}"/stacks/*/*/docker-compose.yml; do
    node="${f#"${PROJECT_DIR}"/stacks/}"; node="${node%%/*}"
    [[ -n "${node_ip[$node]:-}" ]] || { echo "  ! ${f#"${PROJECT_DIR}"/}: '${node}' is not in NODE_IPS — skipped" >&2; continue; }
    while IFS= read -r label; do
      dns_lines+=("address=/${label}.${DOMAIN}/${node_ip[$node]}")
    done < <(router_labels "$f")
  done
  shopt -u nullglob
fi
mapfile -t dns_lines < <(printf '%s\n' "${dns_lines[@]}" | sed '/^$/d' | sort -u)
set_env PIHOLE_DNSMASQ_LINES "$(join "${dns_lines[@]}" filter-AAAA)"
echo "  Pi-hole: ${#dns_lines[@]} Traefik host name(s) → their node"

# ── 4. Data directories ───────────────────────────────────────────────────────
log "Data directories"
DATA_DIR="$(get "${PROJECT_DIR}/.env" DATA_DIR)"; DATA_DIR="${DATA_DIR:-/srv/data}"
PUID="$(get "${PROJECT_DIR}/.env" PUID)"; PUID="${PUID:-$(id -u)}"
PGID="$(get "${PROJECT_DIR}/.env" PGID)"; PGID="${PGID:-$(id -g)}"
sudo install -d -m 755 "${DATA_DIR}/pihole" "${DATA_DIR}/netalertx"          # images manage ownership
sudo install -d -m 750 -o "$PUID" -g "$PGID" "${DATA_DIR}/ntfy" "${DATA_DIR}/gatus"  # run as PUID
sudo install -d -m 700 "${DATA_DIR}/traefik/letsencrypt"                         # acme.json: private keys
echo "  ${DATA_DIR}/{pihole,netalertx,ntfy,gatus,traefik}"

# ── 5. Secrets ────────────────────────────────────────────────────────────────
log "Secrets (./generate-secrets.sh)"
secrets_ok=1
"${DIR}/generate-secrets.sh" || secrets_ok=0

log "Done"
if [[ $pending -eq 0 && $secrets_ok -eq 1 ]]; then
  echo "Ready. Next: sudo ./firewall.sh, then bring the apps up in README.md's order."
else
  echo "Some values are still missing (listed above). Re-run ./setup-secrets.sh once you have them."
  exit 1
fi
