#!/usr/bin/env bash
set -Eeuo pipefail
node_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node="$(basename "$node_dir")"
root="$(cd "$node_dir/../.." && pwd)"
if [[ $# -eq 0 ]]; then
  exec python3 "$root/scripts/fleet.py" plan "$node"
fi
exec python3 "$root/scripts/fleet.py" deploy "$node" "$@"
