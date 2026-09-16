#!/usr/bin/env bash
#
# firewall.sh — percolator's UFW rules. Idempotent: ufw skips rules it has.
#
#   sudo ./firewall.sh            apply
#   sudo ./firewall.sh --dry-run  print the commands only
#
# init/purrbrews-init.sh already set: deny incoming, SSH from the LAN, and
# ufw-docker (which blocks Docker-published ports until allowed). This adds
# what percolator's stacks need, and nothing is ever added by hand.
#
# Only Traefik (80/443) and Authelia (9091, for other nodes' ForwardAuth)
# publish ports. Everything else is reached through Traefik on the `proxy`
# network, or is bound to 127.0.0.1 (LLDAP's admin port).
#
# Published container ports go through the FORWARD chain, so they need
# `ufw route` rules (ufw-docker), not plain `ufw allow`.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

LAN_CIDR="$({ grep -E '^LAN_CIDR=' "${DIR}/.env.local" 2>/dev/null || true; } | tail -n1 | cut -d= -f2-)"
LAN_CIDR="${LAN_CIDR:-192.168.0.0/24}"
[[ "$LAN_CIDR" =~ ^[0-9.]+/[0-9]+$ ]] || { echo "LAN_CIDR looks wrong: $LAN_CIDR" >&2; exit 1; }

FORWARD_AUTH_CLIENTS="$({ grep -E '^FORWARD_AUTH_CLIENTS=' "${DIR}/.env.local" 2>/dev/null || true; } | tail -n1 | cut -d= -f2- | tr -d "'\"")"
FORWARD_AUTH_CLIENTS="${FORWARD_AUTH_CLIENTS:-192.168.0.10}"
for ip in $FORWARD_AUTH_CLIENTS; do
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "FORWARD_AUTH_CLIENTS entry looks wrong: $ip" >&2; exit 1; }
done

run() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then echo "$*"; else "$@"; fi
}
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

command -v ufw >/dev/null || { echo "ufw not installed — run init's firewall step first." >&2; exit 1; }

# Traefik: HTTP (redirects to HTTPS) and HTTPS, from the LAN. sieve's
# cloudflared is on the LAN too, so tunnel traffic is covered.
run ufw route allow proto tcp from "$LAN_CIDR" to any port 80  comment 'percolator: traefik http'
run ufw route allow proto tcp from "$LAN_CIDR" to any port 443 comment 'percolator: traefik https'

# Authelia: ForwardAuth from the other nodes' Traefik only. Never the LAN: the
# port is plain HTTP and serves the login portal too.
for ip in $FORWARD_AUTH_CLIENTS; do
  run ufw route allow proto tcp from "$ip" to any port 9091 comment "percolator: authelia forward-auth from ${ip}"
done

[[ "${DRY_RUN:-0}" -eq 1 ]] || ufw status verbose
