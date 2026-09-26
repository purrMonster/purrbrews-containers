#!/usr/bin/env bash
#
# setup-kiosk.sh: the wall dashboard. Host-native, because it needs the
# laptop's own display and GPU; a browser in a container would only add
# passthrough trouble for one single-purpose screen.
#
# cage (a Wayland compositor that shows exactly one app, full screen) runs
# Chromium in --kiosk mode, autologged-in on tty1 as a dedicated `kiosk` user.
# Not barista: the account that logs itself in on a screen in the hallway
# shouldn't be the one with sudo.
#
#   ./render-configs.sh            # renders kiosk/bash_profile (needs KIOSK_URL)
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
