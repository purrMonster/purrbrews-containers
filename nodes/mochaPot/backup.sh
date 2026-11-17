#!/usr/bin/env bash
# Same on every node: the logic is in stacks/_lib/backup.sh, what to back up in each app's backup file.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$here/../../stacks/_lib/backup.sh" "$here" "$@"
