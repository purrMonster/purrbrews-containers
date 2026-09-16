#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (DOMAIN/GRINDER_LAN_IP/TZ/ROASTERY_LAN_IP) plus its own
# secrets.env.local. Same mechanics as every other node's compose.sh.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh n8n up -d
#   ./compose.sh openwebui logs -f
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

# grinder_net -- n8n, the embedding worker, and postgres-vector join this
# so n8n and the worker can reach Postgres by container name without
# publishing its port to the LAN. openwebui, karakeep, fittrackee, traccar,
# esphome and speedtest-tracker don't need it (no cross-app traffic on
# this node yet) but joining costs nothing and keeps the option open.
# esphome needs network_mode: host for mDNS discovery of ESP32 devices and
# structurally can't join this network -- same exception as every other
# node's host-networked apps.
docker network inspect grinder_net >/dev/null 2>&1 || docker network create grinder_net >/dev/null

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
