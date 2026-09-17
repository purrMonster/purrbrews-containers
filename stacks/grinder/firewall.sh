#!/usr/bin/env bash
#
# firewall.sh — grinder's UFW rules, as code. Idempotent; run after init and
# after any change here:   sudo ./firewall.sh        (--dry-run to print only)
#
# init/purrbrews-init.sh already set: deny incoming, SSH from the LAN,
# ufw-docker. UFW skips rules that already exist, so re-running only adds
# what's new. Rules are tagged "purrbrews grinder:"; see them with
# sudo ufw status numbered.
#
# Added 2026-09-16 alongside the rest of the fleet's firewall.sh scripts --
# this stack previously shipped with none at all (see README "Known gaps"
# before this date).
#
# Two kinds of rule, depending on how the app is networked:
#   host networking  (esphome)                              → INPUT chain → ufw allow
#   published ports  (traefik + every app's backdoor port)   → DOCKER-USER  → ufw route allow
#
# Every app fronted by Traefik keeps its own direct port open too (the
# deliberate backdoor documented in traefik/docker-compose.yml) -- each one
# gets its own route-allow rule below rather than being left to whatever
# ufw-docker's default happens to be.
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ $DRY -eq 1 || $EUID -eq 0 ]] || { echo "Run with sudo (or --dry-run)." >&2; exit 1; }

get() { local l; l="$(grep -E "^$1=" "${DIR}/.env.local" | tail -n1 || true)"; l="${l#*=}"; l="${l#\'}"; printf '%s' "${l%\'}"; }
[[ -f "${DIR}/.env.local" ]] || { echo ".env.local missing — run ./setup-secrets.sh first." >&2; exit 1; }

LAN_CIDR="$(get LAN_CIDR)"
[[ -n "$LAN_CIDR" && "$LAN_CIDR" != *REPLACE_ME* ]] || { echo "LAN_CIDR is not set in .env.local." >&2; exit 1; }

rule() {  # rule <comment> <ufw args...>
  local comment="purrbrews grinder: $1"; shift
  if [[ $DRY -eq 1 ]]; then
    printf 'ufw %s comment %q\n' "$*" "$comment"
  else
    printf '%-44s ' "$comment"; ufw "$@" comment "$comment"
  fi
}

# ── ESPHome (host network, 6052) ─────────────────────────────────────────────
rule "esphome dashboard from LAN" allow proto tcp from "$LAN_CIDR" to any port 6052

# ESPHome runs on the host; Traefik arrives from grinder_net.
# Override for --dry-run on a workstation without Docker.
PROXY_SUBNET="${PROXY_SUBNET:-$(docker network inspect grinder_net --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' | head -n1)}"
[[ -n "$PROXY_SUBNET" && "$PROXY_SUBNET" != *:* ]] || { echo 'Cannot determine grinder_net IPv4 subnet.' >&2; exit 1; }
rule "esphome from proxy" allow proto tcp from "$PROXY_SUBNET" to any port 6052

# ── Traefik (published 80, 443) ──────────────────────────────────────────────
rule "traefik http from LAN"  route allow proto tcp from "$LAN_CIDR" to any port 80
rule "traefik https from LAN" route allow proto tcp from "$LAN_CIDR" to any port 443

# ── Every app's own backdoor port (published, fronted by Traefik too) ───────
rule "fittrackee from LAN"       route allow proto tcp from "$LAN_CIDR" to any port 5001
rule "karakeep from LAN"         route allow proto tcp from "$LAN_CIDR" to any port 3030
rule "n8n from LAN"              route allow proto tcp from "$LAN_CIDR" to any port 5678
rule "openwebui from LAN"        route allow proto tcp from "$LAN_CIDR" to any port 8081
rule "speedtest-tracker from LAN" route allow proto tcp from "$LAN_CIDR" to any port 8765
rule "traccar ui from LAN"       route allow proto tcp from "$LAN_CIDR" to any port 8082
rule "traccar osmand ingest from LAN" route allow proto tcp from "$LAN_CIDR" to any port 5055

[[ $DRY -eq 1 ]] || { ufw reload >/dev/null; echo; ufw status numbered | grep -E 'purrbrews grinder|Status'; }
