# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables set here are used by the scripts that source this
#
# common.sh: sourced by the other scripts in _lib, never run on its own.
#
# The rule I keep coming back to: nothing in _lib knows which node it is on.
# Everything that differs between nodes lives in stacks/<node>/node.conf, and
# everything that differs between apps lives in files inside the app's folder
# (data-dirs, secrets.conf, firewall, *.template, prepare.sh). If I ever catch
# myself writing `if node == sieve` in here, that belongs in node.conf instead.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS="$(cd "$LIB/.." && pwd)"
ROOT="$(cd "$STACKS/.." && pwd)"
SCRIPT="${SCRIPT:-$(basename "$0")}"

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
warn() { printf '%s: %s\n' "$SCRIPT" "$*" >&2; }
die()  { warn "$*"; exit 1; }

not_root() {
  # sudo here leaves root-owned .env.local / secrets files behind, and the next
  # normal run can't rewrite them. The scripts call sudo themselves when needed.
  [[ $EUID -ne 0 ]] || die "run this as the ops user, not with sudo."
}

# load_node <node dir>
# Sets NODE_DIR, NODE_NAME, ENV_LOCAL, ENV_FILES and whatever node.conf sets.
load_node() {
  NODE_DIR="$(cd "${1:?node directory required}" && pwd)"
  NODE_NAME="$(basename "$NODE_DIR")"
  [[ -f "$NODE_DIR/node.conf" ]] || die "$NODE_DIR has no node.conf."

  # Defaults, so a short node.conf is still a valid one.
  APPS=()
  NETWORK=''
  NETWORK_SUBNET_KEY=''
  RESOLVER=''
  NEEDS_INIT=true
  # shellcheck source=/dev/null
  source "$NODE_DIR/node.conf"

  ENV_LOCAL="$NODE_DIR/.env.local"
  # Later files win. Fleet-wide facts first, then what init wrote for this
  # machine, then this node's own settings. An app's secrets.env.local goes
  # on the end wherever an app is involved.
  ENV_FILES=("$STACKS/fleet.env" "$ROOT/.env" "$ENV_LOCAL")
}

app_dirs() {
  # Every folder with a docker-compose.yml or a template, so --list can point
  # out an app that exists on disk but was never added to node.conf.
  local d
  for d in "$NODE_DIR"/*/; do
    d="${d%/}"
    [[ -f "$d/docker-compose.yml" ]] && basename "$d"
  done
  return 0
}

# ── .env files ───────────────────────────────────────────────────────────────
# These are read, never sourced, outside the renderer: a value with a $ in it
# (password hashes) must come back exactly as written.

env_get() {  # env_get <file> <KEY>: last value, one layer of quotes removed
  local line
  [[ -f "$1" ]] || return 0
  line="$(grep -E "^$2=" "$1" | tail -n1)" || true
  line="${line#*=}"
  if [[ "$line" =~ ^\'(.*)\'$ || "$line" =~ ^\"(.*)\"$ ]]; then
    line="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$line"
}

env_has() { [[ -f "$1" ]] && grep -qE "^$2=" "$1"; }

env_value() {  # env_value <KEY> [app]: effective value across ENV_FILES
  local file value=''
  for file in "${ENV_FILES[@]}" ${2:+"$NODE_DIR/$2/secrets.env.local"}; do
    env_has "$file" "$1" && value="$(env_get "$file" "$1")"
  done
  printf '%s' "$value"
}

is_placeholder() { [[ -z "$1" || "$1" == *REPLACE_ME* ]]; }

env_quote() {
  # Plain values stay unquoted: Komodo's onboarding key only worked once it was
  # written without quotes. Anything with $, spaces or shell punctuation gets
  # single quotes, which both bash and docker compose take literally.
  if [[ "$1" =~ ^[A-Za-z0-9_@%+=:,./-]*$ ]]; then
    printf '%s' "$1"
  else
    printf "'%s'" "$1"
  fi
}

env_put() {  # env_put <file> <KEY> <value>: replace in place (keeps order) or append
  local file="$1" key="$2" value="$3" line tmp
  [[ "$value" != *"'"* && "$value" != *$'\n'* ]] \
    || die "not storing $key: its value has a single quote or a newline."
  line="${key}=$(env_quote "$value")"
  [[ -f "$file" ]] || (umask 077 && : > "$file")
  tmp="$(mktemp "${file}.XXXXXX")"
  if env_has "$file" "$key"; then
    LINE="$line" KEY="$key" awk '
      index($0, ENVIRON["KEY"] "=") == 1 { if (!done) print ENVIRON["LINE"]; done = 1; next }
      { print }' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    [[ ! -s "$tmp" || -z "$(tail -c1 "$tmp")" ]] || printf '\n' >> "$tmp"
    printf '%s\n' "$line" >> "$tmp"
  fi
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

migrate_renamed_keys() {
  # When a key gets a better name, the old line is left alone and the value is
  # copied to the new name. That way a node that pulls before anyone runs
  # setup still starts its containers with the right values.
  local old new
  [[ -f "$ENV_LOCAL" ]] || return 0
  while read -r old new _; do
    [[ -z "$old" || "$old" == \#* ]] && continue
    if env_has "$ENV_LOCAL" "$old" && ! env_has "$ENV_LOCAL" "$new"; then
      env_put "$ENV_LOCAL" "$new" "$(env_get "$ENV_LOCAL" "$old")"
      note "copied $old to its new name $new in .env.local"
    fi
  done < "$LIB/renamed-keys"
}

# ── docker / sudo ────────────────────────────────────────────────────────────

use_docker() {
  # The ops user is deliberately not in the docker group (that's passwordless
  # root), so docker goes through sudo. On roastery Docker Desktop answers
  # without it, and there is no sudo anyway.
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  else
    DOCKER=(sudo docker)
  fi
  SUDO=()
  [[ $EUID -eq 0 ]] || ! command -v sudo >/dev/null || SUDO=(sudo)
}

export_env() {  # export_env [app]: every env file into this shell, for host-side scripts
  local f
  set -a
  for f in "${ENV_FILES[@]}" ${1:+"$NODE_DIR/$1/secrets.env.local"}; do
    if [[ -f "$f" ]]; then
      # shellcheck source=/dev/null
      source "$f"
    fi
  done
  set +a
}
