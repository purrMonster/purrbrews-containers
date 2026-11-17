# shellcheck shell=bash
#
# fleet.sh — the fleet's node list, read from a checkout of this repo. Source it
# (with node-mac.sh); it defines functions only. Used by the payload
# (purrbrews-node.sh) and by scripts/fleet-macs.sh, so the static leases
# Pi-hole hands out and the MAC a node puts on its own interface always agree.
#
# A node is a folder under nodes/ with a node.conf. Its address is
# <NODE>_LAN_IP in stacks/fleet.env, and its MAC comes from NODE_MACS in
# payload/payload.env or is derived from its name (node-mac.sh).
#
# Files are read, never sourced: nothing in them is executed.

# kv_get <file> <KEY>: the last value of KEY, one layer of quotes removed.
kv_get() {
  local line
  [[ -f "$1" ]] || return 0
  line="$(grep -E "^$2=" "$1" | tail -n1)" || true
  line="${line#*=}"
  line="${line%$'\r'}"
  if [[ "$line" =~ ^\'(.*)\'$ || "$line" =~ ^\"(.*)\"$ ]]; then
    line="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$line"
}

valid_ipv4() {
  local IFS=. o
  local -a p
  read -r -a p <<< "$1"
  [[ ${#p[@]} -eq 4 ]] || return 1
  for o in "${p[@]}"; do [[ "$o" =~ ^[0-9]{1,3}$ && "$o" -le 255 ]] || return 1; done
}

# fleet_list <repo root> <payload.env>: "name ip mac" per node, in address order.
# Fails (prints why) on a node with no address, a bad address or MAC, or two
# nodes sharing either.
fleet_list() {
  local root="$1" settings="$2" dir name ip mac pair key overrides out=''
  local -A seen_ip=() seen_mac=()
  overrides="$(kv_get "$settings" NODE_MACS)"
  for dir in "$root"/nodes/*/; do
    dir="${dir%/}"
    [[ -f "$dir/node.conf" ]] || continue
    name="${dir##*/}"
    key="${name^^}_LAN_IP"
    ip="$(kv_get "$root/stacks/fleet.env" "$key")"
    valid_ipv4 "$ip" || { echo "fleet: $key in stacks/fleet.env is '$ip', not an IPv4 address." >&2; return 1; }
    mac="$(derive_mac "$name")"
    for pair in $overrides; do
      if [[ "${pair%%=*}" == "$name" || "${pair%%=*}" == "${name,,}" ]]; then
        mac="$(normalize_mac "${pair#*=}")" || { echo "fleet: NODE_MACS gives $name '${pair#*=}', which is not a MAC." >&2; return 1; }
        mac_is_usable "$mac" || { echo "fleet: NODE_MACS gives $name $mac, a multicast or zero address." >&2; return 1; }
      fi
    done
    [[ -z "${seen_ip[$ip]:-}" ]] || { echo "fleet: $name and ${seen_ip[$ip]} both have $ip." >&2; return 1; }
    [[ -z "${seen_mac[$mac]:-}" ]] || { echo "fleet: $name and ${seen_mac[$mac]} would share MAC $mac; set one in NODE_MACS." >&2; return 1; }
    seen_ip[$ip]="$name"; seen_mac[$mac]="$name"
    out+="$name $ip $mac"$'\n'
  done
  [[ -n "$out" ]] || { echo "fleet: no nodes under $root/nodes." >&2; return 1; }
  printf '%s' "$out" | sort -t ' ' -k2,2V
}

# fleet_node <repo root> <name>: the nodes/ spelling of a name, matched
# case-insensitively, or nothing.
fleet_node() {
  local dir base
  for dir in "$1"/nodes/*/; do
    dir="${dir%/}"
    [[ -f "$dir/node.conf" ]] || continue
    base="${dir##*/}"
    if [[ "${base,,}" == "${2,,}" ]]; then printf '%s' "$base"; return 0; fi
  done
  return 1
}
