#!/usr/bin/env bash
# prepare.sh: run by compose.sh before `up`. The satellite reaches the mic and
# speaker through the ops user's PipeWire; without its socket the container
# would start, loop and never hear anything. Say so instead.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
uid="$(sed -n 's/^PUID=//p' "$root/.env" 2>/dev/null | head -n 1)"
uid="${uid:-$(id -u)}"
if [[ ! -S "/run/user/$uid/pulse/native" ]]; then
  echo "voice-satellite: no PipeWire socket at /run/user/$uid/pulse/native." >&2
  echo "  Once per machine: sudo $here/host-setup.sh (docs/voice.md)." >&2
  exit 1
fi
