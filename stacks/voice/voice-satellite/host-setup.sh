#!/usr/bin/env bash
#
# host-setup.sh: once per voice machine (sieve, percolator, cellar), with sudo.
# Gives the ops user a PipeWire that runs with nobody logged in, so the
# voice-satellite container can reach the room's mic and speaker through its
# PulseAudio socket (docs/voice.md). Safe to re-run.
#
#   sudo ./host-setup.sh                       set up, then list the devices
#   sudo ./host-setup.sh --list                only list the devices
#   sudo ./host-setup.sh --sink <name> --source <name>
#                                              also make those the defaults
#                                              (names from --list)
#
# What it changes on the machine, and how to undo each:
#   - packages pipewire, pipewire-pulse, wireplumber, pulseaudio-utils,
#     alsa-utils (apt purge them);
#   - the ops user in the audio group (gpasswd -d <user> audio);
#   - lingering for the ops user, so its user services run from boot
#     (loginctl disable-linger <user>);
#   - a WirePlumber setting in the user's ~/.config that stops it waiting
#     for a logged-in seat before it uses the sound cards (delete
#     ~/.config/wireplumber/wireplumber.conf.d/80-purrbrews-headless.conf).
#
set -euo pipefail
die() { printf 'host-setup: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

LIST_ONLY=0; SINK=''; SOURCE=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST_ONLY=1; shift ;;
    --sink) SINK="${2:?--sink needs a name}"; shift 2 ;;
    --source) SOURCE="${2:?--source needs a name}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$1'" ;;
  esac
done
[[ $EUID -eq 0 ]] || die "run with sudo."

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
uid="$(sed -n 's/^PUID=//p' "$root/.env" 2>/dev/null | head -n 1)"
[[ "$uid" =~ ^[0-9]+$ ]] || die "no PUID in $root/.env; is this a node checkout (the payload writes it)?"
user="$(getent passwd "$uid" | cut -d: -f1)"
home="$(getent passwd "$uid" | cut -d: -f6)"
[[ -n "$user" && -d "$home" ]] || die "uid $uid (PUID) has no account with a home here."
run="/run/user/$uid"
as_user() {
  runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="$run" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$run/bus" "$@"
}

list_devices() {
  echo "Speakers (sinks):"
  as_user pactl list short sinks | awk '{print "  " $2}'
  echo "Microphones (sources; .monitor ones are the speakers' loopback, not mics):"
  as_user pactl list short sources | awk '$2 !~ /\.monitor$/ {print "  " $2}'
  echo "Defaults: sink $(as_user pactl get-default-sink), source $(as_user pactl get-default-source)"
}

if [[ $LIST_ONLY -eq 1 ]]; then
  [[ -S "$run/pulse/native" ]] || die "no PipeWire socket yet; run this without --list first."
  list_devices
  exit 0
fi

echo "== Packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
  pipewire pipewire-pulse wireplumber pulseaudio-utils alsa-utils >/dev/null
note "pipewire, pipewire-pulse, wireplumber, pulseaudio-utils, alsa-utils"

echo "== The ops user ($user)"
usermod -aG audio "$user"
loginctl enable-linger "$user"
for _ in $(seq 1 20); do [[ -S "$run/bus" ]] && break; sleep 0.5; done
[[ -S "$run/bus" ]] || die "$user's user session didn't start ($run/bus missing); check: loginctl user-status $user"
note "in the audio group; lingering on, so its PipeWire runs from boot"

# WirePlumber normally only opens the sound cards for a user with an active
# seat (someone logged in at the console). Nobody ever is on a node.
conf_dir="$home/.config/wireplumber/wireplumber.conf.d"
install -d -o "$user" -g "$(id -gn "$user")" -m 755 "$home/.config" "$home/.config/wireplumber" "$conf_dir"
cat > "$conf_dir/80-purrbrews-headless.conf" <<'CONF'
# Written by stacks/voice/voice-satellite/host-setup.sh: use the sound cards
# without a logged-in seat (this is a headless node).
wireplumber.profiles = {
  main = {
    monitor.alsa.seat-monitoring = disabled
    monitor.bluez.seat-monitoring = disabled
  }
}
CONF
chown "$user:$(id -gn "$user")" "$conf_dir/80-purrbrews-headless.conf"
note "WirePlumber: no seat needed ($conf_dir/80-purrbrews-headless.conf)"

echo "== PipeWire"
as_user systemctl --user daemon-reload
as_user systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
as_user systemctl --user restart wireplumber.service pipewire.service pipewire-pulse.service
for _ in $(seq 1 20); do [[ -S "$run/pulse/native" ]] && break; sleep 0.5; done
[[ -S "$run/pulse/native" ]] || die "no PulseAudio socket at $run/pulse/native; check: systemctl --user -M $user@ status pipewire-pulse"
as_user pactl info >/dev/null || die "pactl can't talk to PipeWire."
note "running; socket $run/pulse/native"

if [[ -n "$SINK" ]]; then as_user pactl set-default-sink "$SINK" || die "no sink '$SINK' (see --list)."; fi
if [[ -n "$SOURCE" ]]; then as_user pactl set-default-source "$SOURCE" || die "no source '$SOURCE' (see --list)."; fi

echo
list_devices
echo
echo "If the defaults above aren't the USB speaker and the conference mic, run again with"
echo "--sink and --source. Then: ./compose.sh voice-satellite up -d (docs/voice.md)."
