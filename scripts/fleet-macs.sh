#!/usr/bin/env bash
#
# fleet-macs.sh — every node's name, address and fixed MAC, from this checkout.
#
#   bash scripts/fleet-macs.sh [--format table|csv|dnsmasq|pihole]
#
#   table    human-readable (default)
#   csv      name,ip,mac: what stacks/_lib/refresh-dns.sh feeds the Pi-holes
#   dnsmasq  dhcp-host=MAC,IP,name
#   pihole   Pi-hole v6 dhcp.hosts entries, for pasting into its settings
#
# The same list the bootstrap payload uses to give each node its address and
# MAC (payload/lib/fleet.sh), so Pi-hole's static leases and the nodes always
# agree. Addresses come from stacks/fleet.env, MACs from payload/payload.env's
# NODE_MACS or the node's name. Needs no root and runs anywhere with bash 4.
#
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../payload/lib/node-mac.sh
source "$ROOT/payload/lib/node-mac.sh"
# shellcheck source=../payload/lib/fleet.sh
source "$ROOT/payload/lib/fleet.sh"

format=table
case "${1:-}" in
  --format) format="${2:?--format needs a value}" ;;
  '') ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
esac

list="$(fleet_list "$ROOT" "$ROOT/payload/payload.env")"
case "$format" in
  table)
    printf '%-12s %-15s %s\n' NODE IP MAC
    while read -r n ip mac; do printf '%-12s %-15s %s\n' "$n" "$ip" "$mac"; done <<< "$list" ;;
  csv)
    echo 'name,ip,mac'
    while read -r n ip mac; do printf '%s,%s,%s\n' "$n" "$ip" "$mac"; done <<< "$list" ;;
  dnsmasq)
    while read -r n ip mac; do printf 'dhcp-host=%s,%s,%s\n' "$mac" "$ip" "$n"; done <<< "$list" ;;
  pihole)
    printf 'hosts = [\n'
    while read -r n ip mac; do printf '  "%s,%s,%s",\n' "$mac" "$ip" "$n"; done <<< "$list"
    printf ']\n' ;;
  *) echo "Unknown format '$format' (table, csv, dnsmasq, pihole)." >&2; exit 1 ;;
esac
