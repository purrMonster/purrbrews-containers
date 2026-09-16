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

# barista is not in the docker group (infrastructure.md §6), so docker
# runs through sudo unless we're already root. Same DOCKER=(...) pattern as
# sieve's and percolator's compose.sh -- reused for BOTH docker calls below
# (network + compose) so there's exactly one sudo elevation per invocation,
# not one per command. Previously this script called bare `docker` with no
# elevation at all, which either failed outright for barista (permission
# denied on the socket) or forced wrapping the whole script in an external
# `sudo ./compose.sh ...` — and since that external sudo doesn't cover a
# *second*, separate `docker` call the same way a single internal one does,
# it could still prompt more than once. Fixed to match sieve/percolator.
DOCKER=(docker); [[ $EUID -eq 0 ]] || DOCKER=(sudo docker)

# cellar_net — every containerized app on this stack joins it (Scrutiny,
# Diun, Komodo's three services, Samba, and now Traefik — added
# 2026-09-16). Same idempotent-create pattern as every other node's
# compose.sh. An app that needs to reach another app on cellar by
# container name doesn't need a compose.sh change to get it, just a
# `networks:` line in its own docker-compose.yml. restic and NFS are not
# containers and never touch this network — see their own directories.
"${DOCKER[@]}" network inspect cellar_net >/dev/null 2>&1 || "${DOCKER[@]}" network create cellar_net >/dev/null

ENV_ARGS=()
[[ -f "${DIR}/.env.local" ]] && ENV_ARGS+=(--env-file "${DIR}/.env.local")
[[ -f "${APP_DIR}/secrets.env.local" ]] && ENV_ARGS+=(--env-file "${APP_DIR}/secrets.env.local")

exec "${DOCKER[@]}" compose --project-directory "$APP_DIR" -f "${APP_DIR}/docker-compose.yml" "${ENV_ARGS[@]}" "$@"
