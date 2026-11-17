#!/usr/bin/env bash
#
# restic-init.sh: create the backup repository. Once, by hand, on cellar,
# after `sudo ./backup.sh keys` and `sudo ./restic/repo-setup.sh` there. It
# goes through the SFTP account like every other job, so the repository's
# files belong to that account from the start.
#
# The nightly jobs deliberately never create it: backing up into a
# repository that silently wasn't the real one is exactly how the old rsync
# mirror went unnoticed for weeks.
#
set -Eeuo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_lib/common.sh
source "$DIR/../../_lib/common.sh"
# shellcheck source=../../_lib/restic-env.sh
source "$LIB/restic-env.sh"
load_node "$(this_node_dir)"
[[ $EUID -eq 0 ]] || die "run with sudo: the repository is reached with root's backup key."
command -v restic >/dev/null || die "restic isn't installed (apt install restic)."

restic_env
reach_repo 30 || die "$REPO_HOST isn't answering on port 22; is sshd running?"

if "${RESTIC[@]}" cat config >/dev/null 2>&1; then
  echo "There's already a repository at $RESTIC_REPOSITORY; nothing to do."
  exit 0
fi
echo "Creating the restic repository at $RESTIC_REPOSITORY"
"${RESTIC[@]}" init
cat <<EOF

Done. Before anything else:
  - copy RESTIC_PASSWORD (restic/secrets.env.local) to the recovery kit.
    Without it every copy of the repository, cellar's and Drive's, is
    unreadable;
  - paste the same value into each node's restic/secrets.env.local, via
    ./setup-secrets.sh there (it asks for it).
EOF
