#!/usr/bin/env bash
#
# compose.sh — thin wrapper so each app dir's docker-compose.yml sees the
# shared .env.local (TZ) plus its own secrets.env.local, if it has one. Same
# mechanics as every other node's compose.sh, with one deliberate
# difference: it does NOT create a shared docker network. roastery isn't a
# dedicated fleet server -- immich-ml is the only app here today, and
# nothing needs to reach it by container name. Add a network here if a
# second app ever needs to talk to another roastery app directly.
#
# Usage: ./compose.sh <app> <docker compose args...>
#   ./compose.sh immich-ml up -d
#   ./compose.sh immich-ml logs -f
#
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 <app> <docker compose args...>" >&2; exit 1; }

APP="$1"; shift
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${DIR}/${APP}"

[[ -d "$APP_DIR" ]] || { echo "No such app: $APP (looked in $APP_DIR)" >&2; exit 1; }
[[ -f "${APP_DIR}/docker-compose.yml" ]] || { echo "No docker-compose.yml in $APP_DIR" >&2; exit 1; }

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec docker compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
