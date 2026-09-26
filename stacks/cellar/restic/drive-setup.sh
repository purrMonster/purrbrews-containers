#!/usr/bin/env bash
#
# drive-setup.sh: one-time setup of rclone for the Google Drive copy. Writes
# /etc/purrbrews/rclone.conf (root, 600) with three remotes:
#
#   roastery     SFTP into roastery's backup target, read-only in practice:
#                where drive-sync.sh reads the repository from
#   drive        Google Drive, on my own API client (README: why)
#   drive-crypt  drive:purrbrews-restic, with names and folders encrypted
#
# Why not a rendered template any more: rclone writes the OAuth token back
# into its config every time it refreshes it, and render-configs would
# overwrite that file (and the token with it) on the next run. So the config
# is rclone's own file, made here once, and backed up with /etc/purrbrews.
#
# Needs from restic/secrets.env.local (./setup-secrets.sh):
#   RCLONE_DRIVE_CLIENT_ID, RCLONE_DRIVE_CLIENT_SECRET   your Google API client
#   RCLONE_CRYPT_PASSWORD, RCLONE_CRYPT_SALT            generated; to flask
#
#   sudo ./restic/drive-setup.sh            make whatever remote is missing
#   sudo ./restic/drive-setup.sh --token    redo the Drive authorization
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$DIR/.."
[[ $EUID -eq 0 ]] || die "run with sudo: the config holds the Drive token and lives in $BACKUP_ETC."
command -v rclone >/dev/null || die "rclone isn't installed (apt install rclone)."
RCLONE_CONF="$BACKUP_ETC/rclone.conf"
REDO_TOKEN=0
[[ "${1:-}" == --token ]] && REDO_TOKEN=1

secret() {  # secret <KEY>: from restic/secrets.env.local, or dies saying what's missing
  local v
  v="$(env_value "$1" restic)"
  is_placeholder "$v" && die "$1 isn't set; run ./setup-secrets.sh (restic/secrets.conf asks for it)."
  printf '%s' "$v"
}
has_remote() { rclone listremotes --config "$RCLONE_CONF" 2>/dev/null | grep -qx "$1:"; }
rc() { rclone --config "$RCLONE_CONF" "$@"; }

install -d -m 755 "$BACKUP_ETC"
[[ -f "$RCLONE_CONF" ]] || (umask 077 && : > "$RCLONE_CONF")
chmod 600 "$RCLONE_CONF"
restic_env
[[ -n "$REPO_HOST" ]] || die "BACKUP_REPOSITORY isn't an sftp: one; nothing for rclone to read from."

# ── roastery (SFTP) ──────────────────────────────────────────────────────────
if has_remote roastery; then
  note "roastery: already there"
else
  # shell_type none: roastery's account is sftp-only (internal-sftp in a
  # chroot), so rclone mustn't try to run md5sum or df there.
  rc config create roastery sftp \
    host="$REPO_HOST" user="${REPO_USER_HOST%@*}" \
    key_file="$BACKUP_KEY" known_hosts_file="$BACKUP_KNOWN_HOSTS" \
    shell_type=none disable_hashcheck=true --non-interactive >/dev/null
  note "roastery: made (sftp $REPO_USER_HOST, key $BACKUP_KEY)"
fi

# ── drive ────────────────────────────────────────────────────────────────────
if has_remote drive && [[ $REDO_TOKEN -eq 0 ]]; then
  note "drive: already there (--token to authorize again)"
else
  id="$(secret RCLONE_DRIVE_CLIENT_ID)"
  secret_value="$(secret RCLONE_DRIVE_CLIENT_SECRET)"
  cat <<EOF

Drive needs a browser once, and cellar has none. On roastery (rclone for
Windows: winget install Rclone.Rclone), in PowerShell:

    rclone authorize "drive" "$id" "<RCLONE_DRIVE_CLIENT_SECRET>"

(the secret is in restic/secrets.env.local here). Sign in with the Google
account that should hold the backups, then paste the one line of JSON it
prints, starting with {"access_token":
EOF
  read -r -p "token> " token
  [[ "$token" == \{*\"refresh_token\"*\} ]] || die "that isn't rclone's token JSON (it needs a refresh_token); nothing changed."
  has_remote drive && rc config delete drive
  # Written as-is rather than through `rclone config create`, which would
  # start its own browser flow. From here on rclone refreshes the token and
  # writes it back to this file itself.
  printf '\n[drive]\ntype = drive\nclient_id = %s\nclient_secret = %s\nscope = drive\ntoken = %s\n' \
    "$id" "$secret_value" "$token" >> "$RCLONE_CONF"
  note "drive: made"
fi

# ── drive-crypt ──────────────────────────────────────────────────────────────
if has_remote drive-crypt; then
  note "drive-crypt: already there"
else
  # --obscure: rclone stores these obscured, not encrypted; the plain values
  # stay in restic/secrets.env.local and in flask. Lose them and whatever is
  # on Drive can't be read, even with RESTIC_PASSWORD.
  rc config create drive-crypt crypt \
    remote=drive:purrbrews-restic filename_encryption=standard directory_name_encryption=true \
    password="$(secret RCLONE_CRYPT_PASSWORD)" password2="$(secret RCLONE_CRYPT_SALT)" \
    --obscure --non-interactive >/dev/null
  note "drive-crypt: made (drive:purrbrews-restic)"
fi

log "Checking"
rc lsd drive: --max-depth 1 >/dev/null && note "drive: signed in" \
  || die "drive doesn't answer: an OAuth error means run this with --token; a 403 means the client ID/secret aren't yours."
rc mkdir drive-crypt:repo && note "drive-crypt: writable"
if wake_roastery 120 && rc lsd "roastery:$REPO_PATH" >/dev/null 2>&1; then
  note "roastery: the repository is readable over SFTP"
else
  warn "roastery: couldn't list $REPO_PATH over SFTP yet (asleep, or cellar's key not authorized there)."
fi
echo
echo "Done. RCLONE_CRYPT_PASSWORD and RCLONE_CRYPT_SALT go to flask with RESTIC_PASSWORD."
