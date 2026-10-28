#!/usr/bin/env bash
#
# prepare.sh: run by compose.sh before `up`. Writes proxy.env.local (gitignored)
# with Traefik's current address on `proxy`, as a /32.
#
# Why: purrCafe takes the signed-in user from Remote-User / Remote-Groups and
# only believes them from AUTH_TRUSTED_PROXY_CIDRS. The other apps here trust
# PROXY_SUBNET, but for them that only decides the client's IP; here it would
# decide who you are, and any container on `proxy` could claim to be an admin
# and read everyone's mail. So: Traefik alone.
#
# Traefik's address isn't pinned, so it can change when Traefik is recreated.
# After `./compose.sh traefik up -d`, run `./compose.sh purrcafe up -d` too;
# until then the dashboard answers every request with 401.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/proxy.env.local"

SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

ip="$("${SUDO[@]}" docker inspect -f '{{with index .NetworkSettings.Networks "proxy"}}{{.IPAddress}}{{end}}' traefik 2>/dev/null || true)"
if [[ ! "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  echo "purrcafe/prepare.sh: Traefik isn't running on the proxy network; bring it up first (./compose.sh traefik up -d)." >&2
  exit 1
fi

want="AUTH_TRUSTED_PROXY_CIDRS=${ip}/32"
if [[ "$(cat "$out" 2>/dev/null)" != "$want" ]]; then
  printf '%s\n' "$want" > "$out"
  chmod 600 "$out"
  echo "purrcafe/prepare.sh: trusting Traefik at ${ip}/32"
fi
