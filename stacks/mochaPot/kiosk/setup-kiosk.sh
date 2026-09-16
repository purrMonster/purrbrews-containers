#!/usr/bin/env bash
#
# setup-kiosk.sh — the household wall dashboard. Host-native, deliberately
# not a container: this needs the physical display/GPU the x360's kiosk
# session already runs on (init/purrbrews-init.sh installs the "Debian 13
# + kiosk session" OS per infrastructure.md §2's fleet table), and a
# browser in a container gains nothing here that a container would cost in
# GPU passthrough complexity for a single dedicated-purpose laptop.
#
# Uses cage (a minimal Wayland kiosk compositor -- one window, no
# decorations, exits when its one child process exits) + Chromium in
# --kiosk mode, not X11/openbox -- cage is purpose-built for exactly this
# single-app-fullscreen use case and needs far less configuration than
# assembling an X session by hand.
#
# What this does:
#   1. Installs cage + chromium if missing.
#   2. Creates a dedicated `kiosk` system user (not `barista` -- keeps the
#      ops account, which has sudo, separate from the account that
#      auto-logs-in on an unattended household screen).
#   3. Sets up autologin for `kiosk` on the console via a systemd getty
#      override.
#   4. Writes ~kiosk/.bash_profile (rendered from bash_profile.template by
#      ../render-configs.sh first -- run that before this script) so
#      login on tty1 execs straight into cage+Chromium, no desktop
#      environment in between.
#
# Usage:
#   cd ..  && ./setup-secrets.sh          # renders bash_profile.template
#   sudo ./kiosk/setup-kiosk.sh
#
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo ./setup-kiosk.sh)." >&2; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "${DIR}/bash_profile" ]] || {
  echo "bash_profile not found -- run ../render-configs.sh first (needs KIOSK_URL from .env.local)." >&2
  exit 1
}

echo "Installing cage + chromium..."
apt-get update
apt-get install -y cage chromium

if ! id kiosk >/dev/null 2>&1; then
  echo "Creating kiosk user..."
  useradd -m -s /bin/bash -G video,input,render kiosk
fi

install -o kiosk -g kiosk -m 644 "${DIR}/bash_profile" /home/kiosk/.bash_profile

echo "Setting up autologin on tty1..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
EOF

systemctl daemon-reload
systemctl restart getty@tty1.service

echo "Done. Reboot (or switch to tty1) to see the kiosk come up."
echo "Escape hatch: Ctrl+Alt+F2 switches to another tty and logs in as barista."
