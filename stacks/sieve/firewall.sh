#!/usr/bin/env bash
#
# firewall.sh — sieve's UFW rules, as code. Idempotent; run after init and after
# any change here:   sudo ./firewall.sh        (--dry-run to print only)
#
# init/purrbrews-init.sh already set: deny incoming, SSH from the LAN, ufw-docker.
# UFW skips rules that already exist, so re-running only adds what's new. Rules
# are tagged "purrbrews sieve:"; see them with  sudo ufw status numbered.
#
# Two kinds of rule, depending on how the app is networked:
#   host networking  (pihole, netalertx)  → INPUT chain  → ufw allow
#   published ports  (traefik)            → DOCKER-USER  → ufw route allow
# Containers on sieve_edge (Traefik, Gatus) reaching a host-network app come in
# on INPUT from EDGE_SUBNET — that is the only way to Pi-hole's and NetAlertX's UIs,
# which have no login of their own.
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ $DRY -eq 1 || $EUID -eq 0 ]] || { echo "Run with sudo (or --dry-run)." >&2; exit 1; }

get() { local l; l="$(grep -E "^$1=" "${DIR}/.env.local" | tail -n1 || true)"; l="${l#*=}"; l="${l#\'}"; printf '%s' "${l%\'}"; }
[[ -f "${DIR}/.env.local" ]] || { echo ".env.local missing — run ./setup-secrets.sh first." >&2; exit 1; }

LAN_CIDR="$(get LAN_CIDR)"; EDGE_SUBNET="$(get EDGE_SUBNET)"
for v in LAN_CIDR EDGE_SUBNET; do
  [[ -n "${!v}" && "${!v}" != *REPLACE_ME* ]] || { echo "$v is not set in .env.local." >&2; exit 1; }
done

rule() {  # rule <comment> <ufw args...>
  local comment="purrbrews sieve: $1"; shift
  if [[ $DRY -eq 1 ]]; then
    printf 'ufw %s comment %q\n' "$*" "$comment"
  else
    printf '%-44s ' "$comment"; ufw "$@" comment "$comment"
  fi
}

# ── Pi-hole (host network) ───────────────────────────────────────────────────
rule "dns from LAN"          allow proto udp from "$LAN_CIDR"    to any port 53
rule "dns from LAN (tcp)"    allow proto tcp from "$LAN_CIDR"    to any port 53
rule "dns from sieve_edge"   allow proto udp from "$EDGE_SUBNET" to any port 53
# A client's first DHCPDISCOVER comes from 0.0.0.0, so this can't be LAN-scoped.
rule "dhcp"                  allow proto udp from any            to any port 67
# Web UI: only Traefik and Gatus, never the LAN directly (no password).
rule "pihole ui from sieve_edge" allow proto tcp from "$EDGE_SUBNET" to any port 8080

# ── NetAlertX (host network) ─────────────────────────────────────────────────
# Web UI via Traefik/Gatus only; the backend API (20212) gets no rule.
rule "netalertx ui from sieve_edge" allow proto tcp from "$EDGE_SUBNET" to any port 20211

# ── Traefik (published 80, 443) ──────────────────────────────────────────────
rule "traefik https from LAN" route allow proto tcp from "$LAN_CIDR" to "$EDGE_SUBNET" port 443
rule "traefik http from LAN"  route allow proto tcp from "$LAN_CIDR" to "$EDGE_SUBNET" port 80

# gatus, ntfy, cloudflared: nothing inbound. Reached through Traefik or the tunnel.

[[ $DRY -eq 1 ]] || { ufw reload >/dev/null; echo; ufw status numbered | grep -E 'purrbrews sieve|Status'; }
