#!/usr/bin/env bash
#
# compose.sh — thin wrapper so every app dir's docker-compose.yml sees the
# shared .env.local (DOMAIN/CELLAR_LAN_IP/TZ/disk vars) plus its own
# secrets.env.local, without needing to remember --env-file flags every
# time. Same mechanics as every other node's compose.sh — copied verbatim,
# nothing cellar-specific in the logic itself.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh komodo   up -d
#   ./compose.sh scrutiny logs -f
#   ./compose.sh smb      down
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

# cellar_net — every containerized app on this stack joins it (Scrutiny,
# Diun, Komodo's three services, Samba), same idempotent-create pattern as
# every other node's compose.sh. Nothing on cellar routes through it yet
# (no Traefik on this node — see README "Known gaps"), but it's cheap
# insurance: an app that later needs to reach another app on cellar by
# container name doesn't need a compose.sh change to get it, just a
# `networks:` line in its own docker-compose.yml. restic and NFS are not
# containers and never touch this network — see their own directories.
docker network inspect cellar_net >/dev/null 2>&1 || docker network create cellar_net >/dev/null

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
