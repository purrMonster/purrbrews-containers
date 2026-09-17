#!/usr/bin/env bash
# Validate settings and atomically render templates with per-app isolation.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/../_lib/render-configs.sh" "$DIR"
