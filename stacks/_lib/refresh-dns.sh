#!/usr/bin/env bash
# Refresh either Pi-hole without rotating secrets or changing running services.
# Usage: bash stacks/_lib/refresh-dns.sh sieve|mochaPot
set -euo pipefail
[[ ${1:-} == sieve || ${1:-} == mochaPot ]] || { echo 'Usage: refresh-dns.sh sieve|mochaPot' >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo 'Run as the ops user, not sudo.' >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Read the installed fleet settings, not example IPs. pipefail prevents writes
# if the fleet inventory fails. Both nodes must have the same NODE_IPS.
fleet="$(sudo bash "$ROOT/init/purrbrews-mac.sh" list --format csv)"
printf '%s\n' "$fleet" | python3 "$ROOT/stacks/_lib/dns-records.py" --node-dir "$ROOT/stacks/$1"
