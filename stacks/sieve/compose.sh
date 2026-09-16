#!/usr/bin/env bash
#
# compose.sh — run `docker compose` for one of sieve's apps with the right env files.
#
#   ./compose.sh <app> <compose args...>     e.g. ./compose.sh pihole up -d
#   ./compose.sh all   <compose args...>     every app, in bring-up order
#                                            (reverse order for down/stop)
#
# Env files, later ones win:
#   /opt/purrbrews/.env          NODE, NODE_IP, TZ, PUID/PGID, DATA_DIR (init/)
#   .env.local                   node settings (from local.env.example)
#   <app>/secrets.env.local      that app's generated secrets
#
# Also creates the shared sieve_edge network (fixed subnet) if it's missing.
# barista is not in the docker group, so docker runs through sudo.
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${DIR}/../.." && pwd)"
APPS=(unbound pihole ntfy cloudflared traefik gatus netalertx)

die() { echo "compose.sh: $*" >&2; exit 1; }
[[ $# -ge 2 ]] || die "usage: $0 <app|all> <docker compose args...>   apps: ${APPS[*]}"

DOCKER=(docker); [[ $EUID -eq 0 ]] || DOCKER=(sudo docker)

# Read KEY=value from a file without sourcing it (values may contain '$').
env_get() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 0
  line="$(grep -E "^${key}=" "$file" | tail -n1 || true)"
  line="${line#*=}"; line="${line%\"}"; line="${line#\"}"; line="${line%\'}"; line="${line#\'}"
  printf '%s' "$line"
}

[[ -f "${DIR}/.env.local" ]] || die ".env.local is missing — run ./setup-secrets.sh first."
if grep -qE '^[A-Z_]+=.*REPLACE_ME' "${DIR}/.env.local"; then
  die ".env.local still has REPLACE_ME values — run ./setup-secrets.sh."
fi

ensure_edge_network() {
  local subnet have
  subnet="$(env_get "${DIR}/.env.local" EDGE_SUBNET)"
  [[ -n "$subnet" ]] || die "EDGE_SUBNET is not set in .env.local."
  if have="$("${DOCKER[@]}" network inspect sieve_edge --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null)"; then
    [[ "$have" == "$subnet" ]] \
      || die "sieve_edge exists with subnet ${have}, expected ${subnet}. Stop its containers and 'sudo docker network rm sieve_edge'."
  else
    "${DOCKER[@]}" network create --driver bridge --subnet "$subnet" sieve_edge >/dev/null
    echo "compose.sh: created network sieve_edge (${subnet})"
  fi
}

run_app() {
  local app="$1"; shift
  local app_dir="${DIR}/${app}"
  [[ -f "${app_dir}/docker-compose.yml" ]] || die "no such app: ${app} (apps: ${APPS[*]})"

  local args=(--project-directory "$app_dir" -f "${app_dir}/docker-compose.yml")
  [[ -f "${PROJECT_DIR}/.env" ]] && args+=(--env-file "${PROJECT_DIR}/.env")
  args+=(--env-file "${DIR}/.env.local")
  [[ -f "${app_dir}/secrets.env.local" ]] && args+=(--env-file "${app_dir}/secrets.env.local")

  "${DOCKER[@]}" compose "${args[@]}" "$@"
}

target="$1"; shift
ensure_edge_network

if [[ "$target" == all ]]; then
  order=("${APPS[@]}")
  case "$1" in down|stop|rm)
    order=(); for ((i=${#APPS[@]}-1; i>=0; i--)); do order+=("${APPS[$i]}"); done ;;
  esac
  for app in "${order[@]}"; do
    echo "── ${app}"
    run_app "$app" "$@"
  done
else
  run_app "$target" "$@"
fi
