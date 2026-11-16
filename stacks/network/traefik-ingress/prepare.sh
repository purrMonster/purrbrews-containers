#!/usr/bin/env bash
#
# prepare.sh: run by compose.sh before `up`. Two jobs:
#
# 1. Rotation for Traefik's access log. Traefik never rotates its own files,
#    and every request percolator serves lands in that one (CrowdSec reads it),
#    so left alone it fills /srv. A logrotate rule rotates it daily, or sooner
#    past 100 MB, keeps 14 compressed, and sends Traefik USR1 so it reopens
#    the new file (tested 2026-10-08: no line lost across a rotation).
#
# 2. The CrowdSec bouncer plugin's source, at a pinned and verified commit,
#    where Traefik loads it as a local plugin.
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

# ── 1. Access-log rotation ─────────────────────────────────────────────────
LOGROTATE_CONF=/etc/logrotate.d/purrbrews-traefik
want_logrotate() {
  cat <<EOF
# Installed by stacks/percolator/traefik/prepare.sh on every \`up\`; edit it there.
# Traefik's access log, read by CrowdSec. USR1 makes Traefik reopen the file.
${DATA_DIR}/traefik/logs/access.log {
    daily
    maxsize 100M
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    dateext
    dateformat -%Y%m%d-%s
    create 0644 root root
    postrotate
        docker kill --signal=USR1 traefik >/dev/null 2>&1 || true
    endscript
}
EOF
}
if ! command -v logrotate >/dev/null; then
  echo "traefik/prepare.sh: installing logrotate (Traefik's access log needs it)"
  "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq logrotate >/dev/null \
    || echo "traefik/prepare.sh: WARNING: couldn't install logrotate; the access log will grow until it's installed." >&2
fi
if [[ "$(cat "$LOGROTATE_CONF" 2>/dev/null)" != "$(want_logrotate)" ]]; then
  want_logrotate | "${SUDO[@]}" tee "$LOGROTATE_CONF" >/dev/null
  "${SUDO[@]}" chmod 644 "$LOGROTATE_CONF"
  echo "traefik/prepare.sh: access-log rotation installed at $LOGROTATE_CONF"
fi

# ── 2. The CrowdSec bouncer plugin ─────────────────────────────────────────
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
