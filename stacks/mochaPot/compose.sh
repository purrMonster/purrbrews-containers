#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (DOMAIN/MOCHAPOT_LAN_IP/TZ) plus its own
# secrets.env.local. Same mechanics as every other node's compose.sh —
# copied verbatim, nothing mochaPot-specific in the logic itself.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh homeassistant up -d
#   ./compose.sh pihole        logs -f
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

# barista is not in the docker group (infrastructure.md §6), so docker
# runs through sudo unless we're already root. Same DOCKER=(...) pattern as
# sieve's and percolator's compose.sh -- reused for BOTH docker calls below
# so there's exactly one sudo elevation per invocation, not one per
# command. This script previously called bare `docker` with no elevation
# at all — fixed to match sieve/percolator (this was the "asking for a
# separate sudo" bug).
DOCKER=(docker); [[ $EUID -eq 0 ]] || DOCKER=(sudo docker)

# mochapot_net -- created for parity with every other node's compose.sh,
# even though nothing on this stack's current app list actually joins it:
# homeassistant, musicassistant and pihole all need network_mode: host
# (mDNS/UPnP discovery, real LAN DNS/DHCP visibility -- see each app's own
# docker-compose.yml comment), which structurally can't join a bridge
# network at all. Kept anyway so a future bridge-networked app here
# doesn't need a compose.sh change to get it.
## Pinned subnet (2026-09-17, PROXY_SUBNET in local.env.example): Home
# Assistant's reverse-proxy trust check needs a stable CIDR to trust, not
# whatever address Docker's default pool happens to hand Traefik's
# container on a given recreate. Falls back to unpinned creation if
# PROXY_SUBNET isn't set yet, same tolerance as every other REPLACE_ME
# value in this repo -- but note that changes nothing for a network that
# already exists (docker doesn't let you re-subnet in place): remove it
# first (after stopping every container on it) if it was created before
# this line existed.
if ! "${DOCKER[@]}" network inspect mochapot_net >/dev/null 2>&1; then
  SUBNET_ARGS=()
  [[ -f "${DIR}/.env.local" ]] && PROXY_SUBNET="$(grep -E '^PROXY_SUBNET=' "${DIR}/.env.local" | tail -n1 | cut -d= -f2- | tr -d "'\"")"
  [[ -n "${PROXY_SUBNET:-}" && "$PROXY_SUBNET" != *REPLACE_ME* ]] && SUBNET_ARGS=(--subnet "$PROXY_SUBNET")
  "${DOCKER[@]}" network create "${SUBNET_ARGS[@]}" mochapot_net >/dev/null
fi

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec "${DOCKER[@]}" compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
