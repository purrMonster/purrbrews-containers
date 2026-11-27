#!/usr/bin/env bash
#
# install.sh: run Home Assistant's WiZ integration from home-assistant/core
# PR #194638 ("Add signing key support to WiZ") instead of the built-in one,
# or go back to the built-in one.
#
# Newer WiZ firmware (1.38.0 and similar) only accepts signed setPilot
# commands: reads work, every on/off fails with -32602 "Invalid params"
# ("Error while communicating with the WiZ device" in HA). The PR adds a
# signing-key field to the WiZ config flow and needs pywizlight 0.6.7.
# README.md (next to this file) has the why, the key, and when to remove it.
#
# Run as barista on the node that runs homeassistant (node.conf APPS):
#
#   bash stacks/home/homeassistant/wiz-signing/install.sh             # install or update, restart HA
#   bash stacks/home/homeassistant/wiz-signing/install.sh --remove    # back to the built-in wiz, restart HA
#
# --no-restart skips the restart (it takes effect on the next one).
# --force installs even when this HA release already has the signing key.
#
# What it changes on the node: $DATA_DIR/homeassistant/custom_components/wiz
# (copied from ./wiz, root-owned like the rest of /config), then a restart of
# the homeassistant container. Way back: --remove.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../_lib/common.sh
source "$HERE/../../../_lib/common.sh"

ACTION=install RESTART=true FORCE=false
for arg in "$@"; do
  case "$arg" in
    --remove)     ACTION=remove ;;
    --no-restart) RESTART=false ;;
    --force)      FORCE=true ;;
    -h|--help)    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown option '$arg' (try --help)." ;;
  esac
done

not_root
load_node "$(this_node_dir)"
runs_here homeassistant || die "$NODE_NAME doesn't run homeassistant (node.conf APPS); run this where it does."
use_docker

DATA_DIR="$(env_value DATA_DIR)"; DATA_DIR="${DATA_DIR:-/srv/data}"
CC="$DATA_DIR/homeassistant/custom_components"
TARGET="$CC/wiz"
SRC="$HERE/wiz"
CONTAINER=homeassistant

running() { [[ "$("${DOCKER[@]}" inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" == true ]]; }

restart_and_check() {
  $RESTART || { note "Not restarting (--no-restart): takes effect on the next restart."; return 0; }
  local since
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "Restarting Home Assistant"
  bash "$NODE_DIR/compose.sh" homeassistant restart

  # The compose healthcheck has a 5-minute start period; a big setup is slow.
  log "Waiting for it to come back (up to 6 minutes)"
  local status=''
  for _ in {1..72}; do
    status="$("${DOCKER[@]}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
    [[ "$status" == healthy ]] && break
    sleep 5
  done
  if [[ "$status" == healthy ]]; then
    note "Home Assistant is healthy."
  else
    warn "Home Assistant isn't healthy yet (status: ${status:-unknown}). Check: sudo docker logs --tail 80 $CONTAINER"
  fi

  log "WiZ lines in the log since the restart"
  "${DOCKER[@]}" logs --since "$since" "$CONTAINER" 2>&1 \
    | grep -iE 'custom integration wiz|requirements for wiz|pywizlight|components\.wiz|\[wiz\]' \
    | tail -n 20 || note "(none yet)"
}

if [[ "$ACTION" == remove ]]; then
  if [[ -d "$TARGET" ]]; then
    log "Removing $TARGET (the built-in WiZ integration takes over again)"
    "${SUDO[@]}" rm -rf "$TARGET"
  else
    note "$TARGET isn't there; nothing to remove."
    RESTART=false
  fi
  restart_and_check
  note "Stored signing keys stay in the WiZ entries; the built-in integration ignores them until it gains the same option."
  exit 0
fi

[[ -f "$SRC/manifest.json" ]] || die "$SRC/manifest.json is missing; is this checkout complete?"

# Once a Home Assistant release has the signing key itself, this override is
# only in the way: it would pin the WiZ code at this PR's version for good.
if running; then
  if "${DOCKER[@]}" exec "$CONTAINER" grep -q CONF_SIGNING_KEY \
      /usr/src/homeassistant/homeassistant/components/wiz/const.py 2>/dev/null; then
    if $FORCE; then
      warn "this Home Assistant release already has WiZ signing-key support; installing anyway (--force)."
    else
      die "this Home Assistant release already has WiZ signing-key support. Use --remove instead (or --force)."
    fi
  fi
else
  note "The $CONTAINER container isn't running; skipping the check for built-in signing support."
fi

version="$(grep -oE '"version": *"[^"]+"' "$SRC/manifest.json" | cut -d'"' -f4)"
log "Installing WiZ ${version} to $TARGET"
"${SUDO[@]}" mkdir -p "$CC"
if [[ -d "$TARGET" ]]; then
  note "Replacing the existing custom wiz."
  "${SUDO[@]}" rm -rf "$TARGET"
fi
"${SUDO[@]}" cp -R "$SRC" "$TARGET"
"${SUDO[@]}" find "$TARGET" -name __pycache__ -type d -prune -exec rm -rf {} +
"${SUDO[@]}" chown -R 0:0 "$TARGET"
"${SUDO[@]}" chmod -R u=rwX,go=rX "$TARGET"

restart_and_check

if running; then
  # Home Assistant installs a custom integration's requirements on startup.
  pw="$("${DOCKER[@]}" exec "$CONTAINER" python3 -c \
    'import sys; sys.path.insert(0, "/config/deps"); import importlib.metadata as m; print(m.version("pywizlight"))' 2>/dev/null || true)"
  note "pywizlight in the container: ${pw:-not found yet (it installs when the WiZ entries load)}"
fi

cat <<'EOF'

Next, in Home Assistant: Settings → Devices & services → WiZ → each entry's
⋮ menu → Reconfigure, and paste the udp_signing_key (one per WiZ home, the
same for every bulb in it). Then toggle a light to check.
EOF
