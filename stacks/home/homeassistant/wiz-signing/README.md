# WiZ signing key (temporary)

A stopgap until Home Assistant ships WiZ signing-key support. `wiz/` is the WiZ
integration from home-assistant/core PR
[#194638](https://github.com/home-assistant/core/pull/194638) ("Add signing key
support to WiZ"), at commit `34c32b7` (2026-11-25), installed as a custom
integration so it takes the built-in one's place. **Remove it once a release has
the fix** (below).

## Why

Newer WiZ firmware (1.38.0 and similar) answers every request with `"env":"pro"`
and an `hmac`, and only accepts *signed* commands. Reads still work, so the bulbs
show up in HA with their state, but every on/off fails:

```
Error during service call to light.turn_on: Error while communicating with the WiZ device
```

Underneath that the bulb returns `-32602 Invalid params`. To confirm on a bulb
(an unsigned turn-on; `-32602` in the reply means it needs signing):

```sh
echo '{"method":"setPilot","params":{"state":true}}' | nc -u -w2 <bulb-ip> 38899
```

pywizlight 0.6.7 signs requests when it's given the key. The built-in integration
in 2026.11.x pins 0.6.3 and has nowhere to enter the key; the PR adds both.
Tracked in home-assistant/core#177463 and #183004.

## What's in `wiz/`

The PR's `homeassistant/components/wiz/` unchanged, plus what a custom integration
needs that a core one doesn't:

- `manifest.json`: a `version` (`0.6.7+pr194638.34c32b7`); HA won't load a custom
  integration without one. Requires `pywizlight==0.6.7`, which HA installs on start.
- `translations/en.json`: built from the PR's `strings.json` with the
  `[%key:…%]` references filled in (core resolves those at build time; a custom
  integration has to ship them resolved).

Everything it imports from Home Assistant exists in 2026.11.2.

## The key

`udp_signing_key` in the WiZ app's export for local integrations: 32 hex
characters, one per WiZ home, the same for every bulb in it. Treat it like a
password: it goes into Home Assistant only, never into this repo. The bulb rejects
a signature more than about a minute old, so the HA host's clock has to be right
(it is, while the node keeps time).

"Allow local communication" must stay on in the WiZ app.

## Install

On the node that runs `homeassistant`, as barista, from the deployed checkout:

```sh
bash stacks/home/homeassistant/wiz-signing/install.sh
```

It copies `wiz/` to `$DATA_DIR/homeassistant/custom_components/wiz`, restarts
Home Assistant, waits for it to be healthy and prints the WiZ log lines. It
refuses if the running release already has the signing key (`--force` overrides).
`--no-restart` skips the restart.

Then in Home Assistant: **Settings → Devices & services → WiZ → each entry's ⋮ →
Reconfigure**, paste the key, and toggle a light. A wrong key gives `-32605
Security error` on the first command; the form only checks the format, because
bulbs don't check signatures on reads.

Expected in the log after the restart: a warning that the custom integration
`wiz` hasn't been tested by Home Assistant. That's this.

## Is it working?

- Settings → System → Logs: no `Error while communicating with the WiZ device`
  when you switch a light
- the light changes, and its state in HA follows

## Remove it (when the fix ships, or if this misbehaves)

```sh
bash stacks/home/homeassistant/wiz-signing/install.sh --remove
```

Deletes the custom `wiz` and restarts; the built-in integration takes over. Do this
**before or with** the upgrade to the release that includes #194638: a custom
integration wins over the built-in one regardless of version, so leaving it would
pin WiZ at this PR forever. The keys stay in the WiZ entries; once the built-in
integration has the option it reads them from the same field (`signing_key`) if
the PR merges as it stands. Check its Reconfigure form after upgrading.

## Updating it from the PR

If the PR changes before it merges and the change matters:

```sh
git clone --filter=blob:none --no-checkout https://github.com/home-assistant/core /tmp/hacore
cd /tmp/hacore && git sparse-checkout set homeassistant/components/wiz
git fetch origin pull/194638/head:pr && git checkout pr
```

Copy `homeassistant/components/wiz/` over `wiz/` here, keep the `version` in
`manifest.json` (bump the commit in it), rebuild `translations/en.json` from
`strings.json`, then install again.
