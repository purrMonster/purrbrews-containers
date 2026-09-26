#!/usr/bin/env bash
# Refresh local DNS and render templates before recreating services.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../_lib/render-configs.sh" "$DIR"
