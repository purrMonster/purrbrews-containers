#!/usr/bin/env bash
set -Eeuo pipefail
node_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$node_dir/scripts/enable-dhcp.sh" "$@"
