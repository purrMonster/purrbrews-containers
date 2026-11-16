# kiosk

The household wall dashboard on mochaPot's own touchscreen (the x360).
Host-native, no `docker-compose.yml`; `setup-kiosk.sh` says why.

## Setup

```sh
cd ..
# make sure KIOSK_URL is set in .env.local first — see local.env.example
./render-configs.sh          # renders kiosk/bash_profile from the template
sudo ./kiosk/setup-kiosk.sh
```

Defaults `KIOSK_URL` to Home Assistant's own dashboard on this same node
(`http://127.0.0.1:8123`, once `../homeassistant` is up) — point it at
whatever dashboard view should actually be shown (a specific HA
`lovelace` view URL, say) once that's decided; not the same thing as just
"Home Assistant is running here."

## What this does, and why host-native

`cage` (a minimal Wayland kiosk compositor) + Chromium in `--kiosk` mode,
autologin on tty1 as a dedicated `kiosk` system user — not `barista` (keeps
the sudo-capable ops account separate from an account that auto-logs-in
unattended), and not a container (this needs the physical
display/GPU the underlying OS session already owns; a container buys
nothing here and costs GPU-passthrough complexity for a single dedicated
laptop).

**Escape hatch**: `Ctrl+Alt+F2` switches to another tty and logs in as
`barista` normally — the kiosk session on tty1 is untouched by that.

## Known gaps

- **Chromium's own updater is off** (`--check-for-update-interval` is a year), but
  the package isn't pinned, so `apt upgrade` still moves it. Nothing here watches host
  packages for updates.
- **No screen-off/wake schedule configured.** The x360's display stays on
  continuously as installed here — reasonable for a wall dashboard,
  wasteful if this ever moves somewhere it's only glanced at occasionally.
- **Crash recovery is by design, still not seen on the hardware.** The profile
  `exec`s cage, so when Chromium exits, cage exits and the tty1 login ends;
  Debian's `getty@.service` has `Restart=always`, so agetty autologs `kiosk` in
  again and the profile starts the kiosk again. To check it: `sudo pkill -x
  chromium` from tty2 or SSH, and the dashboard should be back within seconds.
- **Boot order is handled**: the profile waits up to five minutes for
  `KIOSK_URL` to answer before starting Chromium (2026-10-08), so a power cut
  no longer leaves it on a "can't be reached" page.
