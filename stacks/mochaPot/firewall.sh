#!/usr/bin/env bash
#
# firewall.sh — mochaPot's UFW rules, as code. Idempotent; run after init and
# after any change here:   sudo ./firewall.sh        (--dry-run to print only)
#
# init/purrbrews-init.sh already set: deny incoming, SSH from the LAN,
# ufw-docker. UFW skips rules that already exist, so re-running only adds
# what's new. Rules are tagged "purrbrews mochaPot:"; see them with
# sudo ufw status numbered.
#
# Added 2026-09-16 alongside the rest of the fleet's firewall.sh scripts --
# this stack previously shipped with none at all (see README "Known gaps"
# before this date).
#
# Two kinds of rule, depending on how the app is networked:
#   host networking  (homeassistant, musicassistant, pihole) → INPUT chain → ufw allow
#   published ports  (traefik)                                → DOCKER-USER  → ufw route allow
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ $DRY -eq 1 || $EUID -eq 0 ]] || { echo "Run with sudo (or --dry-run)." >&2; exit 1; }

get() { local l; l="$(grep -E "^$1=" "${DIR}/.env.local" | tail -n1 || true)"; l="${l#*=}"; l="${l#\'}"; printf '%s' "${l%\'}"; }
[[ -f "${DIR}/.env.local" ]] || { echo ".env.local missing — run ./setup-secrets.sh first." >&2; exit 1; }

LAN_CIDR="$(get LAN_CIDR)"
[[ -n "$LAN_CIDR" && "$LAN_CIDR" != *REPLACE_ME* ]] || { echo "LAN_CIDR is not set in .env.local." >&2; exit 1; }

PROXY_SUBNET="$(get PROXY_SUBNET)"
[[ -n "$PROXY_SUBNET" && "$PROXY_SUBNET" != *REPLACE_ME* ]] || { echo 'Set PROXY_SUBNET to mochapot_net actual subnet.' >&2; exit 1; }

rule() {  # rule <comment> <ufw args...>
  local comment="purrbrews mochaPot: $1"; shift
  if [[ $DRY -eq 1 ]]; then
    printf 'ufw %s comment %q\n' "$*" "$comment"
  else
    printf '%-44s ' "$comment"; ufw "$@" comment "$comment"
  fi
}

# ── Home Assistant (host network, 8123) ──────────────────────────────────────
rule "homeassistant ui from LAN" allow proto tcp from "$LAN_CIDR" to any port 8123

# ── Music Assistant (host network, 8095) ─────────────────────────────────────
# mDNS/UPnP discovery and direct-network streaming need the whole LAN
# reachable both ways (musicassistant/docker-compose.yml's own comment) --
# no narrower rule is meaningful here.
rule "musicassistant ui from LAN" allow proto tcp from "$LAN_CIDR" to any port 8095

# ── Pi-hole secondary (host network) ─────────────────────────────────────────
rule "dns from LAN"          allow proto udp from "$LAN_CIDR" to any port 53
rule "dns from LAN (tcp)"    allow proto tcp from "$LAN_CIDR" to any port 53
# Web UI moved off 80 to 8081 (pihole/docker-compose.yml's own comment,
# 2026-09-16 port-conflict fix) -- DHCP stays off on this instance, so
# there's no port 67 rule here, unlike sieve's.
rule "pihole ui from LAN"    allow proto tcp from "$LAN_CIDR" to any port 8081

# Host-network apps receive proxy traffic from the Docker bridge, not LAN_CIDR.
rule "homeassistant from proxy" allow proto tcp from "$PROXY_SUBNET" to any port 8123
rule "musicassistant from proxy" allow proto tcp from "$PROXY_SUBNET" to any port 8095
rule "pihole ui from proxy" allow proto tcp from "$PROXY_SUBNET" to any port 8081

# ── Traefik (published 80, 443) ──────────────────────────────────────────────
rule "traefik http from LAN"  route allow proto tcp from "$LAN_CIDR" to any port 80
rule "traefik https from LAN" route allow proto tcp from "$LAN_CIDR" to any port 443

[[ $DRY -eq 1 ]] || { ufw reload >/dev/null; echo; ufw status numbered | grep -E 'purrbrews mochaPot|Status'; }
