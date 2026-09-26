#!/usr/bin/env bash
#
# prepare.sh: run by compose.sh before `up`. Puts the CrowdSec bouncer
# plugin's source, at a pinned and verified commit, where Traefik loads it as
# a local plugin.
#
# Why local: a catalog plugin is downloaded from plugins.traefik.io on every
# Traefik start. If that download fails, the middleware is invalid and every
# route using it — here, all of them — goes dark. A local copy starts offline.
#
# To upgrade: change PLUGIN_TAG and PLUGIN_COMMIT together (the commit is
# `git ls-remote <repo> refs/tags/<tag>^{}`), then ./compose.sh traefik up -d.
#
set -euo pipefail

PLUGIN_REPO="https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin.git"
PLUGIN_MODULE="github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
PLUGIN_TAG="v1.7.1"
PLUGIN_COMMIT="bef5dfaadbb07381af02ec4e7391e49214ebf953"

DATA_DIR="${1:?usage: prepare.sh <DATA_DIR>}"
DEST="${DATA_DIR}/traefik/plugins-local/src/${PLUGIN_MODULE}"

SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

current="$("${SUDO[@]}" git -c safe.directory='*' -C "$DEST" rev-parse HEAD 2>/dev/null || true)"
if [[ "$current" == "$PLUGIN_COMMIT" ]]; then
  exit 0
fi

echo "traefik/prepare.sh: fetching CrowdSec bouncer plugin ${PLUGIN_TAG}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$PLUGIN_TAG" "$PLUGIN_REPO" "${tmp}/plugin"
got="$(git -C "${tmp}/plugin" rev-parse HEAD)"
if [[ "$got" != "$PLUGIN_COMMIT" ]]; then
  echo "traefik/prepare.sh: ${PLUGIN_TAG} is ${got}, expected ${PLUGIN_COMMIT} — refusing." >&2
  exit 1
fi
"${SUDO[@]}" rm -rf "$DEST"
"${SUDO[@]}" mkdir -p "$(dirname "$DEST")"
"${SUDO[@]}" cp -a "${tmp}/plugin" "$DEST"
"${SUDO[@]}" chown -R 0:0 "${DATA_DIR}/traefik/plugins-local"
echo "traefik/prepare.sh: plugin ready at ${DEST}"
