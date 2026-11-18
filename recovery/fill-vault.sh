#!/bin/bash
# fill-vault.sh: copy the fleet's secrets into flask.kdbx, straight from each
# node into KeePassXC (docs/recovery-kit.md, "What goes in the vault"). Runs on
# americano (macOS's own /bin/bash is enough) or any Linux with KeePassXC.
# It replaces fill-vault.ps1 (deprecated/stacks/roastery/flask).
#
#   ./fill-vault.sh                        the vault on the stick labelled FLASK-A
#   ./fill-vault.sh --vault /path/x.kdbx   a specific vault
#   ./fill-vault.sh --dry-run              which entries it would write, and from where;
#                                          no vault, no password, no values shown
#
# Make the vault first, in KeePassXC (the app): that's where the master
# password is chosen and the settings are seen. This only adds entries to it.
#
# The values never reach the screen, a file or the clipboard: each one is read
# over SSH (as barista, with your key) into memory and handed to keepassxc-cli
# on its standard input. The master password is typed once, hidden. Safe to
# run again: it compares each entry with the node and rewrites only the ones
# whose value has changed (and adds new ones), so this is also how the vault
# is brought up to date after a secret changes. Notes you've edited by hand,
# and entries it doesn't know about, are left alone.
#
# What it copies is recovery/vault.tiers. Not covered, add them by hand:
# barista's sudo password on each node, the 2FA recovery codes, cellar's
# /etc/purrbrews/rclone.conf as an attachment (once Drive is set up), and
# OpenCloud's generated opencloud/config/opencloud.yaml as a protected
# attachment (with the matching whole config/data restic restore).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TIERS="$HERE/vault.tiers"
SSH_USER="${FLASK_SSH_USER:-barista}"
# Tests only: read <dir>/<node>.txt (lines as the remote grep prints them)
# instead of SSH.
TEST_SECRETS="${FLASK_TEST_SECRETS_DIR:-}"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'fill-vault: %s\n' "$*" >&2; exit 1; }

VAULT=''
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT="${2:-}"; [[ -n "$VAULT" ]] || die '--vault needs a path'; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$1' (--vault <path>, --dry-run)" ;;
  esac
done

# ── what to copy ─────────────────────────────────────────────────────────────
T_TIER=(); T_NAME=(); T_PERNODE=()
while read -r tier name flag; do
  [[ -z "${tier:-}" || "$tier" == \#* ]] && continue
  T_TIER+=("$tier"); T_NAME+=("$name"); T_PERNODE+=("${flag:-}")
done < "$TIERS"
[[ ${#T_NAME[@]} -gt 0 ]] || die "no secrets listed in $TIERS."
pattern="$(IFS='|'; printf '%s' "${T_NAME[*]}")"

# ── the vault and keepassxc-cli ──────────────────────────────────────────────
CLI=''
if [[ $DRY -eq 0 ]]; then
  if [[ -z "$VAULT" ]]; then
    if [[ "$(uname -s)" == Darwin ]]; then
      if [[ -d /Volumes/FLASK-A ]]; then VAULT=/Volumes/FLASK-A/flask.kdbx; fi
    else
      part="$(blkid -L FLASK-A 2>/dev/null || true)"
      mnt="${part:+$(lsblk -no MOUNTPOINT "$part" | head -n 1)}"
      if [[ -n "$mnt" ]]; then VAULT="$mnt/flask.kdbx"; fi
    fi
    [[ -n "$VAULT" ]] || die 'no FLASK-A stick mounted; plug it in, or give --vault <path>.'
  fi
  [[ -f "$VAULT" ]] || die "no vault at $VAULT. Make it in KeePassXC first (Database > New Database), then run this again."
  for c in "${FLASK_KPX_CLI:-}" /Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli "$(command -v keepassxc-cli 2>/dev/null || true)"; do
    if [[ -n "$c" && -x "$c" ]]; then CLI="$c"; break; fi
  done
  [[ -n "$CLI" ]] || die 'keepassxc-cli not found (it comes with KeePassXC: install the app, or the .dmg on the stick).'
fi

# keepassxc-cli reads the master password, then any entry password, from
# standard input, one per line. printf is a shell builtin, so neither shows
# up in the process list. Its output is never shown: it's only prompts, and
# `show` would be a value.
kpx() {  # kpx <entry password or ''> <cli args...>
  local value="$1"; shift
  if [[ -n "$value" ]]; then
    printf '%s\n%s\n' "$MASTER" "$value" | "$CLI" "$@" >/dev/null 2>&1
  else
    printf '%s\n' "$MASTER" | "$CLI" "$@" >/dev/null 2>&1
  fi
}
current_password() {  # current_password <entry path>: for comparing, never for showing
  printf '%s\n' "$MASTER" | "$CLI" show -q -s -a Password "$VAULT" "$1" 2>/dev/null
}

MASTER=''
if [[ $DRY -eq 0 ]]; then
  if [[ -n "${FLASK_TEST_MASTER:-}" ]]; then MASTER="$FLASK_TEST_MASTER"
  else read -rs -p "Master password for $VAULT: " MASTER; echo; fi
  kpx '' ls -q "$VAULT" || die "that password doesn't open $VAULT."
fi

# ── read the secrets from the nodes ──────────────────────────────────────────
step 'Reading the nodes (values stay in memory)'
F_NAME=(); F_WHERE=(); F_VALUE=()
for conf in "$ROOT"/nodes/*/node.conf; do
  node="$(basename "$(dirname "$conf")")"
  key="$(printf '%s' "$node" | tr '[:lower:]' '[:upper:]')_LAN_IP"
  ip="$(sed -n "s/^$key=//p" "$ROOT/stacks/fleet.env" | head -n 1)"
  [[ -n "$ip" ]] || { warn "$node: no $key in stacks/fleet.env; skipped."; continue; }
  if [[ -n "$TEST_SECRETS" ]]; then
    lines="$(cat "$TEST_SECRETS/$node.txt" 2>/dev/null || true)"; code=0
  else
    code=0
    lines="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$ip" \
      "grep -HE '^($pattern)=' /opt/purrbrews/stacks/*/*/secrets.env.local /opt/purrbrews/nodes/*/.env.local 2>/dev/null" \
      2>/dev/null)" || code=$?
  fi
  # grep's 1 is "nothing found"; anything above is SSH or grep failing.
  if [[ $code -gt 1 ]]; then warn "$node ($ip): couldn't read it over SSH; its secrets are missing from this run."; continue; fi
  n=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    file="${line%%:*}"; kv="${line#*:}"
    name="${kv%%=*}"; value="${kv#*=}"
    case "$file" in
      /opt/purrbrews/stacks/*/*/secrets.env.local)
        app="${file%/secrets.env.local}"; app="${app##*/}"; where="$node/$app" ;;
      /opt/purrbrews/nodes/*/.env.local) where="$node/.env.local" ;;
      *) continue ;;
    esac
    if [[ ${#value} -ge 2 && ( "$value" == \"*\" || "$value" == \'*\' ) ]]; then value="${value:1:${#value}-2}"; fi
    [[ -z "$value" || "$value" == *REPLACE_ME* ]] && continue
    F_NAME+=("$name"); F_WHERE+=("$where"); F_VALUE+=("$value"); n=$((n + 1))
  done <<< "$lines"
  say "  $node: $n secret(s)"
done

# ── write them ───────────────────────────────────────────────────────────────
step "Writing ${VAULT:-(dry run)}"
added=0; changed=0; same=0; failed=''; missing=''; made_groups=''
write_entry() {  # write_entry <group> <title> <value> <notes>
  local path="$1/$2" current
  if [[ $DRY -eq 1 ]]; then say "  would write  $path  ($4)"; return; fi
  if [[ " $made_groups " != *" $1 "* ]]; then
    kpx '' mkdir -q "$VAULT" "$1" || true   # fails harmlessly if it's there
    made_groups="$made_groups $1"
  fi
  if current="$(current_password "$path")"; then
    if [[ "$current" == "$3" ]]; then same=$((same + 1)); return; fi
    if kpx "$3" edit -q -p "$VAULT" "$path"; then changed=$((changed + 1)); say "  changed  $path  (the node has a new value)"
    else failed="$failed $path"; fi
  else
    if kpx "$3" add -q -p --notes "$4" "$VAULT" "$path"; then added=$((added + 1)); say "  added    $path  ($4)"
    else failed="$failed $path"; fi
  fi
}

# Written for macOS's bash 3.2, where "${a[@]}" of an empty array trips set -u:
# every array loop below runs only once the array is known to be non-empty.
found=${#F_NAME[@]}
for t in "${!T_NAME[@]}"; do
  name="${T_NAME[$t]}"; group="Tier ${T_TIER[$t]}"
  idx=()
  if [[ $found -gt 0 ]]; then
    for i in "${!F_NAME[@]}"; do
      if [[ "${F_NAME[$i]}" == "$name" ]]; then idx+=("$i"); fi
    done
  fi
  if [[ ${#idx[@]} -eq 0 ]]; then missing="$missing $name"; continue; fi
  # The same key on several nodes (RESTIC_PASSWORD) is one entry when every
  # copy agrees; one per node when they don't, or when it's per node anyway.
  agree=1
  for i in "${idx[@]}"; do [[ "${F_VALUE[$i]}" == "${F_VALUE[${idx[0]}]}" ]] || agree=0; done
  if [[ $agree -eq 1 && "${T_PERNODE[$t]}" != per-node ]]; then
    notes=''
    for i in "${idx[@]}"; do notes="${notes:+$notes, }${F_WHERE[$i]}"; done
    write_entry "$group" "$name" "${F_VALUE[${idx[0]}]}" "$notes"
    continue
  fi
  [[ "${T_PERNODE[$t]}" == per-node ]] || warn "$name differs between nodes; one entry per node. Worth finding out why."
  for i in "${idx[@]}"; do
    # keepassxc-cli reads / in an entry path as a group, so a title never has
    # one: "CF_DNS_API_TOKEN (sieve)", or "(sieve traefik)" when that node
    # has the key in two apps.
    node="${F_WHERE[$i]%%/*}"; on_node=0
    for j in "${idx[@]}"; do
      if [[ "${F_WHERE[$j]%%/*}" == "$node" ]]; then on_node=$((on_node + 1)); fi
    done
    if [[ $on_node -gt 1 ]]; then label="${F_WHERE[$i]/\// }"; else label="$node"; fi
    write_entry "$group" "$name ($label)" "${F_VALUE[$i]}" "${F_WHERE[$i]}"
  done
done
MASTER=''; F_VALUE=(); current=''
unset MASTER F_VALUE current

step 'Done'
if [[ $DRY -eq 1 ]]; then say '  Dry run: nothing was written.'
else say "  $added added, $changed changed, $same already up to date."; fi
[[ -z "$missing" ]] || say "  Not set on any node (fine if that app or Drive isn't set up yet):$missing"
[[ -z "$failed" ]] || { warn "keepassxc-cli refused:$failed"; exit 1; }
say ''
say 'Still by hand, in KeePassXC: sudo passwords, 2FA recovery codes, rclone.conf once Drive'
say 'is set up, and opencloud.yaml. Then copy flask.kdbx to FLASK-B and run ./make-flask.sh --check.'
