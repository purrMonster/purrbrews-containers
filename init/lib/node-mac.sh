#!/usr/bin/env bash
#
# node-mac.sh — MAC address helpers shared by purrbrews-init.sh and
# purrbrews-mac.sh. Source it; it defines functions only.
#
# Every node gets a fixed, "cloned" MAC that NetworkManager puts on its wired
# interface instead of the NIC's burned-in one. The router, Pi-hole DHCP
# reservations and ARP tables then see the same identity for a node no matter
# which NIC, USB dongle or reinstall is behind it.
#
# Where a node's MAC comes from, in order:
#   1. NODE_MACS in the env file (name=aa:bb:cc:dd:ee:ff), for a MAC you chose
#      yourself — e.g. to keep a reservation the router already has.
#   2. Derived from the node name: 02:xx:xx:xx:xx:xx, where xx = the first
#      5 bytes of sha256("purrbrews:<lower-case node name>"). Same name →
#      same MAC on every run and every reinstall, with nothing to write down.
#
# 02: in the first byte marks the address as locally administered and unicast
# (IEEE 802), so it can never collide with a real vendor-assigned MAC.

# derive_mac <node>  → prints the derived MAC
derive_mac() {
  local name="${1,,}" hex
  hex="$(printf 'purrbrews:%s' "$name" | sha256sum | cut -c1-10)"
  printf '02:%s:%s:%s:%s:%s\n' "${hex:0:2}" "${hex:2:2}" "${hex:4:2}" "${hex:6:2}" "${hex:8:2}"
}

# normalize_mac <mac> → lower-case colon form; returns 1 if it isn't a MAC
normalize_mac() {
  local m="${1,,}"
  m="${m//-/:}"
  [[ "$m" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]] || return 1
  printf '%s\n' "$m"
}

# mac_is_usable <mac> → 0 if unicast and not all-zero
mac_is_usable() {
  local first=$((16#${1:0:2}))
  (( (first & 1) == 0 )) || return 1                # multicast/broadcast bit set
  [[ "$1" != "00:00:00:00:00:00" ]]
}

# mac_is_local <mac> → 0 if the locally-administered bit is set
mac_is_local() {
  local first=$((16#${1:0:2}))
  (( (first & 2) == 2 ))
}
