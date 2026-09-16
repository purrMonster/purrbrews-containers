# kiosk

The household wall dashboard on mochaPot's own touchscreen (the x360, per
infrastructure.md §2). Host-native, no `docker-compose.yml` here — see
`setup-kiosk.sh`'s own header comment for why.

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

- **Chromium auto-updates are disabled** (`--check-for-update-interval`
  pinned to a year) but the *package* itself isn't pinned — `apt upgrade`
  still moves it. Diun doesn't watch host packages, only container images,
  so there's no update-awareness for this specific piece of the fleet.
  Revisit if that turns out to matter.
- **No screen-off/wake schedule configured.** The x360's display stays on
  continuously as installed here — reasonable for a wall dashboard,
  wasteful if this ever moves somewhere it's only glanced at occasionally.
- **Crash recovery untested.** `cage` exits when its one child (Chromium)
  exits, and nothing currently restarts `cage` or re-triggers the login
  session if that happens outside of a reboot — getty's own respawn
  behavior handles the tty1 login prompt reappearing, but hasn't been
  verified to actually bring the kiosk session back up cleanly without a
  full reboot.
