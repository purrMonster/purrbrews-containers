#!/usr/bin/env bash
# Explicit DHCP handover after every router/other DHCP server is disabled.
# Run as barista; sudo is scoped to inventory and Docker operations.
set -euo pipefail
[[ ${1:-} == --routers-dhcp-disabled ]] || {
  echo 'Usage: bash enable-dhcp.sh --routers-dhcp-disabled' >&2
  echo 'Only use after disabling DHCP on every router/other server on this LAN.' >&2
  exit 1
}
[[ $EUID -ne 0 ]] || { echo 'Run as the ops user, not sudo.' >&2; exit 1; }
[[ $(hostname -s) == sieve ]] || { echo 'This script must run on sieve.' >&2; exit 1; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$DIR/.env.local" ]] || { echo 'Run setup-secrets.sh first.' >&2; exit 1; }

# Preserve all original settings in a private, gitignored backup.
backup="$(mktemp "$DIR/.dhcp-backup.XXXXXX.env.local")"
chmod 600 "$backup"
cat "$DIR/.env.local" > "$backup"
echo "Settings backup: $backup"

# Generate app DNS plus option 6 (.10 and .13 from the installed fleet map).
bash "$DIR/../_lib/refresh-dns.sh" sieve
python3 - "$DIR" <<'PY'
from pathlib import Path
import ipaddress
import runpy
import sys
node = Path(sys.argv[1])
helper = runpy.run_path(str(node.parent / '_lib/dns-records.py'))
path = node / '.env.local'
values = helper['read_env'](path)
network = ipaddress.IPv4Network(values['LAN_CIDR'])
start = ipaddress.IPv4Address(values['PIHOLE_DHCP_START'])
end = ipaddress.IPv4Address(values['PIHOLE_DHCP_END'])
gateway = ipaddress.IPv4Address(values['GATEWAY'])
if not (start in network and end in network and gateway in network and start <= end):
    raise SystemExit('Invalid DHCP range or gateway; DHCP remains unchanged.')
if start <= gateway <= end or start == network.network_address or end == network.broadcast_address:
    raise SystemExit('DHCP range includes gateway/network/broadcast; refusing activation.')
print(f'Compose enables IPv4 DHCP: {start}–{end}; gateway {gateway}')
PY

bash "$DIR/compose.sh" pihole config --quiet
bash "$DIR/compose.sh" pihole up -d --force-recreate
# Wait for FTL configuration AND an actual DHCP socket, not just a container.
for attempt in {1..15}; do
  active="$(sudo docker exec pihole pihole-FTL --config dhcp.active 2>/dev/null || true)"
  if [[ "$active" == true ]] && [[ -n "$(ss -H -lun 'sport = :67')" ]]; then
    echo 'Verified: Pi-hole DHCP is active and UDP port 67 is listening.'
    echo 'Reconnect one affected client and verify its lease, gateway and DNS.'
    exit 0
  fi
  sleep 2
done
echo 'DHCP startup not verified. Inspect: sudo docker logs --tail 80 pihole' >&2
echo "Previous settings are preserved at $backup; do not enable a second DHCP server without disabling this one." >&2
exit 1
