#!/usr/bin/env bash
#
# drive-setup.sh: one-time setup of rclone for the Google Drive copy. Writes
# /etc/purrbrews/rclone.conf (root, 600) with two remotes:
#
#   drive        Google Drive, on my own API client (README: why)
#   drive-crypt  drive:purrbrews-restic, with names and folders encrypted
#
# The repository itself needs no remote: drive-sync.sh reads it from
# cellar's disk. (The old config had a third, `roastery`, for SFTP; an
# existing one is left alone and unused.)
#
# Why not a rendered template any more: rclone writes the OAuth token back
# into its config every time it refreshes it, and render-configs would
# overwrite that file (and the token with it) on the next run. So the config
# is rclone's own file, made here once, and backed up with /etc/purrbrews.
#
# Needs from restic/secrets.env.local (./setup-secrets.sh):
#   RCLONE_DRIVE_CLIENT_ID, RCLONE_DRIVE_CLIENT_SECRET   your Google API client
#   RCLONE_CRYPT_PASSWORD, RCLONE_CRYPT_SALT            generated; to the recovery kit
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
load_node "$(this_node_dir)"
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
REPO_DIR="$(repo_local_path)"

# ── drive ────────────────────────────────────────────────────────────────────
if has_remote drive && [[ $REDO_TOKEN -eq 0 ]]; then
  note "drive: already there (--token to authorize again)"
else
  id="$(secret RCLONE_DRIVE_CLIENT_ID)"
  secret_value="$(secret RCLONE_DRIVE_CLIENT_SECRET)"
  cat <<EOF

Drive needs a browser once, and cellar has none. On americano (rclone for
macOS: brew install rclone), in a terminal:

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
  # stay in restic/secrets.env.local and in the recovery kit. Lose them and whatever is
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
if [[ -f "$REPO_DIR/config" ]]; then
  note "the repository is at $REPO_DIR"
else
  warn "no repository at $REPO_DIR yet (repo-setup.sh, then restic-init.sh); drive-sync.sh refuses until there is."
fi
echo
echo "Done. RCLONE_CRYPT_PASSWORD and RCLONE_CRYPT_SALT go to the recovery kit with RESTIC_PASSWORD."
