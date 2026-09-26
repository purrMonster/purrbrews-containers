#!/usr/bin/env bash
#
# compose.sh: `docker compose` for one app, or all of them, on any node.
# Every node's ./compose.sh is a three-line wrapper that calls this with its
# own directory first.
#
#   ./compose.sh <app> <compose args...>    e.g. ./compose.sh pihole up -d
#   ./compose.sh --all <compose args...>    every app in node.conf order,
#                                           backwards for down/stop/rm
#   ./compose.sh --list                     bring-up order, plus any app folder
#                                           node.conf doesn't mention yet
#
# Env files, later ones win: stacks/fleet.env, /opt/purrbrews/.env (from init),
# the node's .env.local, then the app's own secrets.env.local.
#
# Before up / create / start / restart it also:
#   - copies renamed .env.local keys to their new names (_lib/renamed-keys)
#   - refuses when a rendered config is missing or older than what it's built from
#   - creates the app's data directories from <app>/data-dirs
#   - runs <app>/prepare.sh if there is one
#   - refuses a resolved config that still has a REPLACE_ME in it
#     (only the field names are printed, never the values)
#
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_node "${1:?usage: compose.sh <node dir> ...}"
shift

usage() {
  sed -n '6,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

ensure_network() {
  [[ -n "$NETWORK" ]] || return 0
  local subnet='' have
  if [[ -n "$NETWORK_SUBNET_KEY" ]]; then
    subnet="$(env_value "$NETWORK_SUBNET_KEY")"
    is_placeholder "$subnet" && die "$NETWORK_SUBNET_KEY is not set in .env.local."
  fi
  if have="$("${DOCKER[@]}" network inspect "$NETWORK" --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null)"; then
    # A network can't be re-subnetted in place, and pulling it out from under
    # running containers isn't something I want a wrapper doing on its own.
    if [[ -n "$subnet" && " $have " != *" $subnet "* ]]; then
      warn "network $NETWORK is on ${have% }, but $NETWORK_SUBNET_KEY says $subnet." \
           "Firewall and trusted-proxy rules assume $subnet; stop its containers and" \
           "'sudo docker network rm $NETWORK' when there's a quiet moment."
    fi
  else
    "${DOCKER[@]}" network create --driver bridge ${subnet:+--subnet "$subnet"} "$NETWORK" >/dev/null
    note "created network $NETWORK${subnet:+ ($subnet)}"
  fi
}

make_data_dirs() {
  # <app>/data-dirs: "<path> <uid>:<gid> [mode]" per line. Paths are under
  # DATA_DIR, or under MEDIA_DIR when they start with MEDIA_DIR/. PUID/PGID
  # mean the ops user. Docker creates a missing bind-mount source as
  # root:root, and an image that runs as a fixed non-root user then
  # crash-loops. Directories that already exist are never touched.
  local app_dir="$1" base path owner mode puid pgid full
  [[ -f "$app_dir/data-dirs" ]] || return 0
  puid="$(env_value PUID)"; pgid="$(env_value PGID)"
  while read -r path owner mode; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    base="$(env_value DATA_DIR)"
    if [[ "$path" == MEDIA_DIR/* ]]; then base="$(env_value MEDIA_DIR)"; path="${path#MEDIA_DIR/}"; fi
    [[ -n "$base" ]] || die "DATA_DIR/MEDIA_DIR aren't set; has init/purrbrews-init.sh run on this node?"
    owner="${owner//PUID/$puid}"; owner="${owner//PGID/$pgid}"
    [[ "$owner" =~ ^[0-9]+:[0-9]+$ ]] || die "bad owner in ${app_dir##*/}/data-dirs: $path $owner"
    [[ "$path" != *..* && "$path" != /* ]] || die "bad path in ${app_dir##*/}/data-dirs: $path"
    full="$base/$path"
    [[ -d "$full" ]] && continue
    "${SUDO[@]}" install -d -m "${mode:-750}" -o "${owner%%:*}" -g "${owner##*:}" "$full"
    note "created $full ($owner, ${mode:-750})"
  done < "$app_dir/data-dirs"
}

compose_args() {  # compose_args <app>: fills ARGS for `docker compose`
  local app_dir="$NODE_DIR/$1" f
  ARGS=(--project-directory "$app_dir" -f "$app_dir/docker-compose.yml")
  for f in "${ENV_FILES[@]}" "$app_dir/secrets.env.local"; do
    [[ -f "$f" ]] && ARGS+=(--env-file "$f")
  done
  return 0
}

preflight() {
  local app="$1" app_dir="$NODE_DIR/$1" tpl out f
  if [[ "$NEEDS_INIT" == true && ! -f "$ROOT/.env" ]]; then
    die "$ROOT/.env is missing; run init/purrbrews-init.sh on this node first."
  fi
  [[ -f "$ENV_LOCAL" ]] || die ".env.local is missing; run ./setup-secrets.sh first."

  # Templates are rendered by ./render-configs.sh, not here: rendering is the
  # step that can fail loudly, and I'd rather it didn't happen as a side
  # effect of `up`.
  while IFS= read -r tpl; do
    out="${tpl%.template}"
    [[ -f "$out" ]] || die "${out#"$NODE_DIR"/} hasn't been rendered; run ./render-configs.sh."
    for f in "$tpl" "${ENV_FILES[@]}" "$app_dir/secrets.env.local"; do
      if [[ -f "$f" && "$f" -nt "$out" ]]; then
        die "${out#"$NODE_DIR"/} is older than ${f#"$ROOT"/}; run ./render-configs.sh."
      fi
    done
  done < <(find "$app_dir" -name '*.template' -type f)

  make_data_dirs "$app_dir"

  if [[ -f "$app_dir/prepare.sh" ]]; then
    bash "$app_dir/prepare.sh" "$(env_value DATA_DIR)" || die "$app/prepare.sh failed."
  fi

  compose_args "$app"
  "${DOCKER[@]}" compose "${ARGS[@]}" config --format json \
    | python3 "$LIB/check-compose-config.py" \
    || die "$app: fix the settings above (./setup-secrets.sh asks for them), then try again."
}

run_app() {
  local app="$1"; shift
  [[ -f "$NODE_DIR/$app/docker-compose.yml" ]] || die "no such app: $app (apps: ${APPS[*]})"
  local verb='' arg
  for arg in "$@"; do [[ "$arg" == -* ]] || { verb="$arg"; break; }; done
  case "$verb" in
    up|create|start|restart) preflight "$app" ;;
  esac
  compose_args "$app"
  "${DOCKER[@]}" compose "${ARGS[@]}" "$@"
}

[[ $# -ge 1 ]] || usage
case "$1" in
  -h|--help) usage 0 ;;
  --list)
    printf '%s\n' "${APPS[@]}"
    for app in $(app_dirs); do
      [[ " ${APPS[*]} " == *" $app "* ]] || echo "($app has a docker-compose.yml but isn't in node.conf's APPS)"
    done
    exit 0
    ;;
esac

use_docker
migrate_renamed_keys
ensure_network

target="$1"; shift
[[ $# -ge 1 ]] || usage
if [[ "$target" == --all || "$target" == all ]]; then
  order=("${APPS[@]}")
  case " $* " in
    *" down "*|*" stop "*|*" rm "*)
      order=()
      for ((i = ${#APPS[@]} - 1; i >= 0; i--)); do order+=("${APPS[$i]}"); done
      ;;
  esac
  for app in "${order[@]}"; do
    echo "── $app"
    run_app "$app" "$@" || die "$app failed; stopping here."
  done
else
  run_app "$target" "$@"
fi
