#!/usr/bin/env bash
#
# refresh-dns.sh <node dir>: regenerate the Pi-hole records in a resolver
# node's .env.local without touching secrets or running containers.
# render-configs.sh calls it on nodes with RESOLVER set; recreate pihole
# afterwards (./compose.sh pihole up -d) for the records to take effect.
#
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_node "${1:?usage: refresh-dns.sh <node dir>}"
not_root
[[ "$RESOLVER" == primary || "$RESOLVER" == secondary ]] \
  || die "$NODE_NAME isn't a resolver (RESOLVER in node.conf is '${RESOLVER}')."

# The fleet list from this checkout: addresses from stacks/fleet.env, MACs
# as the bootstrap payload sets them (scripts/fleet-macs.sh). A failed list
# stops here and never turns into an empty set of records.
fleet="$(bash "$ROOT/scripts/fleet-macs.sh" --format csv)"
printf '%s\n' "$fleet" \
  | DNS_SERVERS="$(env_value DNS_PRIMARY),$(env_value DNS_SECONDARY)" \
    python3 "$LIB/dns-records.py" --node-dir "$NODE_DIR" --role "$RESOLVER"
