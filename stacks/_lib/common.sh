# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables set here are used by the scripts that source this
#
# common.sh: sourced by the other scripts in _lib, never run on its own.
#
# The rule I keep coming back to: nothing in _lib knows which node it is on.
# Everything that differs between nodes lives in nodes/<node>/node.conf, and
# everything that differs between apps lives in files inside the app's folder
# (data-dirs, secrets.conf, firewall, *.template, prepare.sh). If I ever catch
# myself writing `if node == sieve` in here, that belongs in node.conf instead.
#
# Since the 2026-11 rebuild an app has one home, stacks/<group>/<app>, whichever
# node runs it; a node is only nodes/<node>/ (node.conf, local.env.example, the
# wrappers and its .env.local). app_dir finds an app by name, so app names are
# unique across the groups.

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS="$(cd "$LIB/.." && pwd)"
ROOT="$(cd "$STACKS/.." && pwd)"
NODES="$ROOT/nodes"
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
  TOOLS=()
  BACKUP_HUB=false
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
  # For an app's own scripts (prepare.sh and the like), which can no longer
  # tell the node from where they sit.
  export PURRBREWS_NODE_DIR="$NODE_DIR"
}

# this_node_dir: the node this checkout runs as, for scripts that live in an
# app's folder and are started by hand or by systemd. The wrappers export
# PURRBREWS_NODE_DIR; otherwise it is NODE in /opt/purrbrews/.env (written when
# the node was set up), then the host name. Names match whatever their case.
this_node_dir() {
  local name d base
  if [[ -n "${PURRBREWS_NODE_DIR:-}" ]]; then
    printf '%s' "$PURRBREWS_NODE_DIR"
    return 0
  fi
  name="$(env_get "$ROOT/.env" NODE)"
  [[ -n "$name" ]] || name="$(hostname -s 2>/dev/null || hostname)"
  for d in "$NODES"/*/; do
    d="${d%/}"
    base="${d##*/}"
    if [[ -f "$d/node.conf" && "${base,,}" == "${name,,}" ]]; then
      printf '%s' "$d"
      return 0
    fi
  done
  die "can't tell which node this is ('$name' has no folder under nodes/); set PURRBREWS_NODE_DIR."
}

# app_dir <app>: the app's folder, stacks/<group>/<app>. Prints nothing when
# there is no such app.
app_dir() {
  local d found=''
  for d in "$STACKS"/*/"${1:?app name required}"; do
    [[ -d "$d" && "$d" != "$LIB"/* ]] || continue
    [[ -z "$found" ]] || die "two folders are called $1: ${found#"$ROOT"/} and ${d#"$ROOT"/}."
    found="$d"
  done
  printf '%s' "$found"
}

runs_here() {  # runs_here <app>: is it in this node's APPS or TOOLS?
  local a
  for a in "${APPS[@]}" "${TOOLS[@]}"; do [[ "$a" == "$1" ]] && return 0; done
  return 1
}

node_app_dirs() {  # the folder of every app and tool this node runs, one per line
  local a d
  for a in "${APPS[@]}" "${TOOLS[@]}"; do
    d="$(app_dir "$a")"
    [[ -n "$d" ]] && printf '%s\n' "$d"
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
  for file in "${ENV_FILES[@]}" ${2:+"$(app_dir "$2")/secrets.env.local"}; do
    env_has "$file" "$1" && value="$(env_get "$file" "$1")"
  done
  printf '%s' "$value"
}

is_placeholder() { [[ -z "$1" || "$1" == *REPLACE_ME* ]]; }

clean_pasted() {  # clean_pasted <value>: what a paste usually brings along, taken off
  # A Windows clipboard adds a \r; a copy from a JSON file or a web page often
  # takes the quotes around the value, or a space. None of those belong to a
  # secret, and a quote left in makes env_put refuse the value.
  local v="${1//$'\r'/}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  if [[ ${#v} -ge 2 && ( ( "$v" == \"*\" ) || ( "$v" == \'*\' ) ) ]]; then v="${v:1:${#v}-2}"; fi
  printf '%s' "$v"
}

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
    || die "not storing $key: its value has a single quote or a newline in it (nothing was changed). Paste only the value itself, then run this again."
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
  for f in "${ENV_FILES[@]}" ${1:+"$(app_dir "$1")/secrets.env.local"}; do
    if [[ -f "$f" ]]; then
      # shellcheck source=/dev/null
      source "$f"
    fi
  done
  set +a
}
