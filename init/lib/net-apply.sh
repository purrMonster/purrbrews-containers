#!/usr/bin/env bash
#
# net-apply.sh — switch an interface to a static NetworkManager profile, with
# automatic rollback. Launched DETACHED by purrbrews-init.sh (systemd-run), so
# an SSH session dropping when the IP changes can't kill it half-way.
#
# Usage: net-apply.sh <iface> <new-con> <addr/cidr> <gateway> <mode> [old-con] [orig-mac] [want-mac]
#   mode = migrate  interface was owned by ifupdown. The caller prepared
#                   /etc/network/interfaces.purrbrews-new (stanza commented out)
#                   and a backup at /etc/network/interfaces.pre-purrbrews.bak.
#   mode = nm       interface was already managed by NetworkManager
#   orig-mac        MAC on the interface before the switch (restored on rollback)
#   want-mac        cloned MAC the new profile sets; empty = keep the current one
#
# Success = the new address (and MAC, if cloning) is on the interface AND the gateway answers
# (ICMP, or at least ARP). Otherwise everything is rolled back within ~60 s,
# so a headless box never ends up unreachable.
#
set -uo pipefail

IFACE="$1"; NEW_CON="$2"; ADDR="$3"; GW="$4"; MODE="$5"; OLD_CON="${6:-}"
ORIG_MAC="${7:-}"; WANT_MAC="${8:-}"
LOG_DIR=/var/log/purrbrews
BACKUP=/etc/network/interfaces.pre-purrbrews.bak
mkdir -p "$LOG_DIR"
exec >>"$LOG_DIR/net-apply.log" 2>&1

ts() { date '+%F %T'; }
say() { echo "$(ts) $*"; }

gateway_ok() {
  ip -4 addr show dev "$IFACE" | grep -q "inet ${ADDR} " || return 1
  if [[ -n "$WANT_MAC" ]]; then
    [[ "$(cat "/sys/class/net/${IFACE}/address")" == "$WANT_MAC" ]] || return 1
  fi
  ip -4 route show default dev "$IFACE" | grep -q "via ${GW} " || return 1
  ping -c1 -W1 -I "$IFACE" "$GW" &>/dev/null && return 0
  ip neigh show "$GW" dev "$IFACE" | grep -Eq 'REACHABLE|STALE|DELAY'
}

say "=== applying $ADDR via $GW on $IFACE (mode=$MODE, new=$NEW_CON, old=${OLD_CON:-none}, mac ${ORIG_MAC:-?} -> ${WANT_MAC:-unchanged}) ==="
sleep 3   # let the caller print its summary first

if [[ "$MODE" == migrate ]]; then
  # ifdown first, with the ORIGINAL stanza still in place, so the DHCP client is stopped.
  ifdown --force "$IFACE" 2>/dev/null || true
  [[ -f /etc/network/interfaces.purrbrews-new ]] && mv -f /etc/network/interfaces.purrbrews-new /etc/network/interfaces
  systemctl disable networking 2>/dev/null || true
  ip addr flush dev "$IFACE" || true
  systemctl restart NetworkManager
  sleep 5
  nmcli device set "$IFACE" managed yes 2>/dev/null || true
fi

nmcli connection up "$NEW_CON" ifname "$IFACE" || say "nmcli connection up returned non-zero"

deadline=$((SECONDS + 60))
while (( SECONDS < deadline )); do
  if gateway_ok; then
    say "SUCCESS: $IFACE is $ADDR (MAC $(cat "/sys/class/net/${IFACE}/address")) and gateway $GW is reachable."
    if [[ "$NEW_CON" == *-next && "$OLD_CON" == "${NEW_CON%-next}" ]]; then
      # Re-run: replace the previous purrbrews profile and take over its name.
      nmcli connection delete "$OLD_CON" >/dev/null || true
      nmcli connection modify "$NEW_CON" connection.id "$OLD_CON" || true
      say "Replaced previous profile '$OLD_CON'."
    elif [[ -n "$OLD_CON" && "$OLD_CON" != "$NEW_CON" ]]; then
      nmcli connection modify "$OLD_CON" connection.autoconnect no || true
      say "Old profile '$OLD_CON' set to autoconnect=no (kept for manual fallback)."
    fi
    touch /etc/purrbrews/.network-applied
    exit 0
  fi
  sleep 2
done

say "FAILED: $ADDR${WANT_MAC:+ / $WANT_MAC} not up or gateway not reachable — rolling back."
nmcli connection down "$NEW_CON" 2>/dev/null || true
nmcli connection delete "$NEW_CON" 2>/dev/null || true
if [[ -n "$ORIG_MAC" && "$(cat "/sys/class/net/${IFACE}/address")" != "$ORIG_MAC" ]]; then
  # Profiles without a cloned MAC "preserve" whatever is on the link, so put
  # the original back before the old configuration comes up.
  ip link set dev "$IFACE" down || true
  if ip link set dev "$IFACE" address "$ORIG_MAC"; then say "Restored MAC $ORIG_MAC."; else say "Could not restore MAC $ORIG_MAC."; fi
  ip link set dev "$IFACE" up || true
fi
if [[ "$MODE" == migrate && -f "$BACKUP" ]]; then
  cp -f "$BACKUP" /etc/network/interfaces
  systemctl restart NetworkManager
  systemctl enable networking 2>/dev/null || true
  systemctl restart networking || ifup "$IFACE" || true
elif [[ -n "$OLD_CON" ]]; then
  nmcli connection up "$OLD_CON" ifname "$IFACE" || true
fi
say "Rollback finished. Previous network configuration restored."
exit 1
