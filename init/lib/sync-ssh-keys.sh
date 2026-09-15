#!/usr/bin/env bash
#
# sync-ssh-keys.sh — keep a user's authorized_keys in step with a central list
# of public keys, so no key is ever pasted onto a node by hand.
#
# Sources (all optional, at least one must yield a key):
#   SSH_KEYS_GITHUB_USERS  space-separated GitHub usernames -> https://github.com/<user>.keys
#   SSH_KEYS_URLS          space-separated https URLs serving authorized_keys-format text
#   SSH_KEYS_LOCAL_FILE    a local authorized_keys-format file
#
# TLS for SSH_KEYS_URLS:
#   SSH_KEYS_PINNED_PUBKEY sha256//<base64>. When set, URL sources are trusted by
#                          this public-key pin instead of a CA — used for the
#                          self-signed purrbrews-bootstrap server on roastery.
#
# Optional allowlist:
#   SSH_KEY_FINGERPRINTS   space-separated SHA256:... fingerprints. When set, ONLY
#                          keys whose fingerprint is listed are installed, so a
#                          compromised GitHub account can't add a key to the fleet.
#
# Behaviour:
#   - Keys live in a managed block inside ~OPS_USER/.ssh/authorized_keys. Lines
#     outside the block (added by hand) are never touched.
#   - Removing a key at the source removes it from every node on the next sync.
#   - Fail-safe: if ANY configured source can't be fetched, or the result would be
#     zero keys, nothing is changed. An outage must never look like "revoke all".
#   - Exit codes: 0 ok, 75 a source was unreachable (e.g. roastery asleep —
#     temporary, nothing changed), 1 anything else.
#
# Usage:  sync-ssh-keys.sh [--config FILE] [--dry-run]
#   Config defaults to /etc/purrbrews/ssh-keys.conf (KEY=value lines).
#   Variables already set in the environment take precedence over the file.
#
set -Eeuo pipefail

CONFIG="/etc/purrbrews/ssh-keys.conf"
DRY_RUN=false
BEGIN_MARK="# >>> purrbrews managed keys (sync-ssh-keys.sh) — edits inside this block are overwritten >>>"
END_MARK="# <<< purrbrews managed keys <<<"

log()  { printf '[ssh-keys] %s\n' "$*"; }
warn() { printf '[ssh-keys] WARNING: %s\n' "$*" >&2; }
die()  { printf '[ssh-keys] ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG="${2:?--config needs a path}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# Minimal KEY=value reader (no shell evaluation). Environment wins over file.
read_config() {
  local file="$1" line key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
    [[ -n "${!key+x}" ]] || printf -v "$key" '%s' "$val"
  done < "$file"
}
read_config "$CONFIG"

OPS_USER="${OPS_USER:-barista}"
SSH_KEYS_GITHUB_USERS="${SSH_KEYS_GITHUB_USERS:-}"
SSH_KEYS_URLS="${SSH_KEYS_URLS:-}"
SSH_KEYS_LOCAL_FILE="${SSH_KEYS_LOCAL_FILE:-}"
SSH_KEY_FINGERPRINTS="${SSH_KEY_FINGERPRINTS:-}"
SSH_KEYS_PINNED_PUBKEY="${SSH_KEYS_PINNED_PUBKEY:-}"
if [[ -n "$SSH_KEYS_PINNED_PUBKEY" && ! "$SSH_KEYS_PINNED_PUBKEY" =~ ^sha256//[A-Za-z0-9+/]{43}=$ ]]; then
  die "SSH_KEYS_PINNED_PUBKEY must look like sha256//<44 base64 chars>."
fi
# Test hook: lets the test suite point "github" at a local server.
GITHUB_KEYS_BASE="${GITHUB_KEYS_BASE:-https://github.com}"

id "$OPS_USER" &>/dev/null || die "User '$OPS_USER' does not exist."
HOME_DIR="$(getent passwd "$OPS_USER" | cut -d: -f6)"
AK_FILE="${AUTHORIZED_KEYS_FILE:-${HOME_DIR}/.ssh/authorized_keys}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------------
: > "$TMP/candidates"   # lines: <source-label>\t<key line>
sources=0

fetch() {  # fetch <url> <outfile> [pinned]
  local tls=()
  [[ "${3:-}" == pinned && -n "$SSH_KEYS_PINNED_PUBKEY" ]] && tls=(-k --pinnedpubkey "$SSH_KEYS_PINNED_PUBKEY")
  curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 5 --max-time 20 --retry 2 --retry-delay 2 \
       "${tls[@]}" -o "$2" "$1"
}
# fetch_or_exit <url> <outfile> [pinned] — a pin/TLS mismatch is a hard error
# (someone else answering as roastery); anything else is "unreachable" (75).
fetch_or_exit() {
  local rc=0
  fetch "$@" || rc=$?
  case "$rc" in
    0) ;;
    90|60|35|51|58) die "TLS verification failed for $1 (curl exit $rc) — pinned key mismatch? Leaving authorized_keys unchanged." ;;
    *) printf '[ssh-keys] UNREACHABLE: %s (curl exit %s) — leaving authorized_keys unchanged.\n' "$1" "$rc" >&2; exit 75 ;;
  esac
}

for gh_user in $SSH_KEYS_GITHUB_USERS; do
  sources=$((sources + 1))
  url="${GITHUB_KEYS_BASE}/${gh_user}.keys"
  fetch_or_exit "$url" "$TMP/src"
  while IFS= read -r l || [[ -n "$l" ]]; do printf 'github:%s\t%s\n' "$gh_user" "$l"; done \
    < "$TMP/src" >> "$TMP/candidates"
done

for url in $SSH_KEYS_URLS; do
  sources=$((sources + 1))
  [[ "$url" == https://* ]] || die "Refusing non-https key URL: $url"
  fetch_or_exit "$url" "$TMP/src" pinned
  while IFS= read -r l || [[ -n "$l" ]]; do printf 'url\t%s\n' "$l"; done \
    < "$TMP/src" >> "$TMP/candidates"
done

if [[ -n "$SSH_KEYS_LOCAL_FILE" ]]; then
  sources=$((sources + 1))
  [[ -r "$SSH_KEYS_LOCAL_FILE" ]] || die "SSH_KEYS_LOCAL_FILE=$SSH_KEYS_LOCAL_FILE is not readable."
  while IFS= read -r l || [[ -n "$l" ]]; do printf 'local\t%s\n' "$l"; done \
    < "$SSH_KEYS_LOCAL_FILE" >> "$TMP/candidates"
fi

[[ $sources -gt 0 ]] || die "No key sources configured (SSH_KEYS_GITHUB_USERS / SSH_KEYS_URLS / SSH_KEYS_LOCAL_FILE)."

# ---------------------------------------------------------------------------
# Validate, filter, de-duplicate
# ---------------------------------------------------------------------------
KEY_TYPES='ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com'
declare -A seen=()
declare -A allow=()
for fp in $SSH_KEY_FINGERPRINTS; do allow["$fp"]=1; done

: > "$TMP/accepted"
: > "$TMP/fingerprints"
while IFS=$'\t' read -r label line; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  # Only plain keys: no authorized_keys options (command=, from=, ...) from remote sources.
  if [[ ! "$line" =~ ^($KEY_TYPES)[[:space:]]+([A-Za-z0-9+/=]+)([[:space:]].*)?$ ]]; then
    warn "Skipping unrecognised line from $label: ${line:0:40}..."
    continue
  fi
  ktype="${BASH_REMATCH[1]}"; kblob="${BASH_REMATCH[2]}"
  printf '%s %s\n' "$ktype" "$kblob" > "$TMP/one.pub"
  if ! info="$(ssh-keygen -lf "$TMP/one.pub" 2>/dev/null)"; then
    warn "Skipping invalid $ktype key from $label."
    continue
  fi
  bits="${info%% *}"; fp="$(awk '{print $2}' <<<"$info")"
  if [[ "$ktype" == ssh-rsa && "$bits" -lt 2048 ]]; then
    warn "Skipping $bits-bit RSA key $fp from $label (too weak)."
    continue
  fi
  if [[ ${#allow[@]} -gt 0 && -z "${allow[$fp]:-}" ]]; then
    warn "Skipping $fp from $label — not in SSH_KEY_FINGERPRINTS allowlist."
    continue
  fi
  [[ -n "${seen[$fp]:-}" ]] && continue
  seen["$fp"]=1
  printf '%s %s purrbrews:%s\n' "$ktype" "$kblob" "$label" >> "$TMP/accepted"
  printf '%s %s\n' "$fp" "$label" >> "$TMP/fingerprints"
done < "$TMP/candidates"

count="$(wc -l < "$TMP/accepted")"
[[ "$count" -gt 0 ]] || die "Zero valid keys after filtering — refusing to empty authorized_keys."

# ---------------------------------------------------------------------------
# Rewrite the managed block (atomically)
# ---------------------------------------------------------------------------
existing=""
[[ -f "$AK_FILE" ]] && existing="$(cat "$AK_FILE")"

# Everything outside the managed block is preserved verbatim.
outside="$(printf '%s\n' "$existing" | awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}' | sed -e '/./,$!d')"   # drop leading blank lines

old_block="$(printf '%s\n' "$existing" | awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
  $0==b {inb=1; next}
  $0==e {inb=0; next}
  inb {print}')"

{
  [[ -n "$outside" ]] && printf '%s\n\n' "$outside"
  printf '%s\n' "$BEGIN_MARK"
  cat "$TMP/accepted"
  printf '%s\n' "$END_MARK"
} > "$TMP/new_ak"

log "Sources: $sources, keys accepted: $count"
while read -r fp label; do log "  $fp  ($label)"; done < "$TMP/fingerprints"

if [[ "$old_block" == "$(cat "$TMP/accepted")" ]]; then
  log "authorized_keys already up to date for $OPS_USER."
  exit 0
fi

if $DRY_RUN; then
  log "--dry-run: would write $AK_FILE:"
  diff -u <(printf '%s\n' "$existing") "$TMP/new_ak" || true
  exit 0
fi

install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "$(dirname "$AK_FILE")"
install -m 600 -o "$OPS_USER" -g "$OPS_USER" "$TMP/new_ak" "${AK_FILE}.purrbrews-tmp"
mv -f "${AK_FILE}.purrbrews-tmp" "$AK_FILE"
log "Updated $AK_FILE."
