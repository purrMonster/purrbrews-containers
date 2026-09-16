#!/usr/bin/env bash
#
# compose.sh — run `docker compose` for one app (or all of them) on this node.
#
#   ./compose.sh <app> <compose args...>      e.g. ./compose.sh immich up -d
#   ./compose.sh --all <compose args...>      every app, in bring-up order
#                                             (reverse order for down/stop)
#   ./compose.sh --list                       apps in bring-up order
#
# For each call it:
#   1. loads, in order: /opt/purrbrews/.env (written by init: NODE_IP, TZ,
#      PUID/PGID, DATA_DIR…), this node's .env.local, and the app's own
#      secrets.env.local;
#   2. creates the shared `proxy` network (fixed subnet) if it is missing;
#   3. before `up`/`create`/`start`/`restart`: refuses to run with REPLACE_ME
#      placeholders or with rendered configs that are missing or older than
#      their template/env files, then creates the app's data directories
#      from <app>/data-dirs with the right owner and runs <app>/prepare.sh
#      if there is one.
#
# barista is not in the docker group, so docker runs through sudo. Run this
# script as barista, not under sudo.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_ENV="$(cd "${DIR}/../.." && pwd)/.env"

# Bring-up order. Each entry only depends on entries before it.
APPS=(traefik crowdsec lldap authelia vaultwarden nextcloud immich paperless mealie vikunja actualbudget freshrss homepage)

die()  { echo "compose.sh: $*" >&2; exit 1; }
warn() { echo "compose.sh: $*" >&2; }

usage() { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

DOCKER=(docker)
[[ $EUID -eq 0 ]] || DOCKER=(sudo docker)
SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

# get_value <file> <KEY> — last value of KEY, surrounding single quotes stripped.
get_value() {
  local line
  line="$(grep -E "^$2=" "$1" 2>/dev/null | tail -n1 || true)"
  line="${line#*=}"; line="${line#\'}"; line="${line%\'}"
  printf '%s' "$line"
}

ensure_network() {
  local subnet
  subnet="$(get_value "${DIR}/.env.local" PROXY_SUBNET)"
  subnet="${subnet:-172.30.0.0/24}"
  if ! "${DOCKER[@]}" network inspect proxy >/dev/null 2>&1; then
    "${DOCKER[@]}" network create --driver bridge --subnet "$subnet" proxy >/dev/null
    echo "compose.sh: created network 'proxy' (${subnet})"
  fi
}

preflight() {
  local app_dir="$1" app f tpl out
  app="$(basename "$app_dir")"

  [[ -f "$ROOT_ENV" ]] || die "${ROOT_ENV} not found — run init/purrbrews-init.sh on this node first."
  [[ -f "${DIR}/.env.local" ]] || die ".env.local not found — run ./setup-secrets.sh first."

  for f in "${DIR}/.env.local" "${app_dir}/secrets.env.local"; do
    [[ -f "$f" ]] || continue
    if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$f"; then
      die "${f#"$DIR"/} still has REPLACE_ME values: $(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=.*REPLACE_ME' "$f" | cut -d= -f1 | tr '\n' ' ')— run ./setup-secrets.sh."
    fi
  done

  while IFS= read -r tpl; do
    out="${tpl%.template}"
    [[ -f "$out" ]] || die "${out#"$DIR"/} has not been rendered — run ./render-configs.sh."
    for f in "$tpl" "${DIR}/.env.local" "${app_dir}/secrets.env.local"; do
      if [[ -f "$f" && "$f" -nt "$out" ]]; then
        die "${out#"$DIR"/} is older than ${f#"$DIR"/} — run ./render-configs.sh."
      fi
    done
  done < <(find "$app_dir" -name '*.template' 2>/dev/null)

  make_data_dirs "$app_dir"

  # Optional per-app hook for anything that must exist before containers
  # start (e.g. traefik's local plugin). Receives DATA_DIR.
  if [[ -x "${app_dir}/prepare.sh" ]]; then
    "${app_dir}/prepare.sh" "$(get_value "$ROOT_ENV" DATA_DIR)" || die "${app}/prepare.sh failed."
  fi
}

# <app>/data-dirs: one "<path under DATA_DIR> <uid>:<gid> [mode]" per line;
# PUID and PGID stand for the ops user from /opt/purrbrews/.env.
# Creating these up front stops Docker from creating bind-mount sources as
# root:root, which crash-loops images that run as a fixed non-root user.
make_data_dirs() {
  local app_dir="$1" data_dir path owner mode
  [[ -f "${app_dir}/data-dirs" ]] || return 0
  data_dir="$(get_value "$ROOT_ENV" DATA_DIR)"
  [[ -n "$data_dir" ]] || die "DATA_DIR missing from ${ROOT_ENV}."
  local puid pgid
  puid="$(get_value "$ROOT_ENV" PUID)"; pgid="$(get_value "$ROOT_ENV" PGID)"
  while read -r path owner mode; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    owner="${owner//PUID/$puid}"; owner="${owner//PGID/$pgid}"
    [[ "$owner" =~ ^[0-9]+:[0-9]+$ ]] || die "bad owner in ${app_dir}/data-dirs: ${path} ${owner}"
    [[ "$path" != *..* ]] || die "bad path in ${app_dir}/data-dirs: $path"
    if [[ ! -d "${data_dir}/${path}" ]]; then
      "${SUDO[@]}" install -d -m "${mode:-750}" -o "${owner%%:*}" -g "${owner##*:}" "${data_dir}/${path}"
      echo "compose.sh: created ${data_dir}/${path} (${owner}, ${mode:-750})"
    fi
  done < "${app_dir}/data-dirs"
}

run_app() {
  local app="$1"; shift
  local app_dir="${DIR}/${app}"
  [[ -f "${app_dir}/docker-compose.yml" ]] || die "no such app: ${app} (expected ${app_dir}/docker-compose.yml)"

  case " $* " in
    *" up "*|*" create "*|*" start "*|*" restart "*) preflight "$app_dir" ;;
  esac

  local env_args=()
  [[ -f "$ROOT_ENV" ]] && env_args+=(--env-file "$ROOT_ENV")
  [[ -f "${DIR}/.env.local" ]] && env_args+=(--env-file "${DIR}/.env.local")
  [[ -f "${app_dir}/secrets.env.local" ]] && env_args+=(--env-file "${app_dir}/secrets.env.local")

  "${DOCKER[@]}" compose --project-directory "$app_dir" -f "${app_dir}/docker-compose.yml" \
    "${env_args[@]}" "$@"
}

[[ $# -ge 1 ]] || usage
case "$1" in
  -h|--help) usage 0 ;;
  --list) printf '%s\n' "${APPS[@]}"; exit 0 ;;
  --all)
    shift; [[ $# -ge 1 ]] || usage
    order=("${APPS[@]}")
    case " $* " in
      *" down "*|*" stop "*|*" rm "*)
        order=(); for ((i=${#APPS[@]}-1; i>=0; i--)); do order+=("${APPS[$i]}"); done ;;
    esac
    ensure_network
    for app in "${order[@]}"; do
      echo "==> ${app}"
      run_app "$app" "$@" || { warn "${app} failed — stopping here."; exit 1; }
    done
    ;;
  *)
    app="$1"; shift; [[ $# -ge 1 ]] || usage
    ensure_network
    run_app "$app" "$@"
    ;;
esac
