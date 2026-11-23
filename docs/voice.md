# Voice

**Each ThinkCentre is a room's voice assistant.** sieve (living room), percolator
and cellar each have a USB speaker and a conference-room mic, and each runs its
own speech-to-text and text-to-speech. Home Assistant on cellar decides what to
do with what was said. Nothing leaves the house; no cloud voice service is
involved (owner, 2026-11-17). The code is `stacks/voice/` (W4, written
2026-11-18); bringing it up is phase 9 of the [migration plan](migration-plan.md).

## How a request flows

```
room mic ──► voice-satellite ──(ESPHome API, tcp/6053)──► Home Assistant (cellar)
             wake word here                                 │
                                                            ├─(Wyoming, tcp/10300)─► whisper   speech → text
                                                            ├─ intent: what to do (Assist)
                                                            └─(Wyoming, tcp/10200)─► piper     text → speech
room speaker ◄── voice-satellite ◄──────── the reply's audio ─┘
```

All three containers run on the room's own machine. Home Assistant's pipeline for
that room names that machine's Whisper and Piper, so each room's speech is
transcribed and its reply spoken by its own ThinkCentre.

| App | Image | Port, open to | Does |
|---|---|---|---|
| `whisper` | `rhasspy/wyoming-whisper` 3.8.1 | tcp/10300, cellar only | speech to text (faster-whisper, CPU) |
| `piper` | `rhasspy/wyoming-piper` 2.5.3 | tcp/10200, cellar only | text to speech |
| `voice-satellite` | `ghcr.io/ohf-voice/linux-voice-assistant` 1.1.18 | tcp/6053 and mDNS, cellar only | wake word, mic in, speaker out |

The Wyoming protocol and the ESPHome API have no authentication of their own, so
the firewall is the guard: each app's `firewall` file lets cellar (Home Assistant's
node, since 2026-11-22) in and nothing else. A test checks it on all three nodes.

## Decisions

- **The satellite is Linux Voice Assistant**, not Wyoming Satellite. Wyoming
  Satellite is no longer maintained; Linux Voice Assistant replaced it. It speaks
  the ESPHome protocol, so Home Assistant adds it as an ESPHome device and gets
  the newer features (timers, stop word, media player, continued conversation).
  The wake word is built in (microWakeWord; "okay nabu" until chosen otherwise
  in HA), so there's no separate openWakeWord service.
- **Audio goes through the host's PipeWire**, as the ops user, over its
  PulseAudio socket, which is how the image expects it. Headless Debian has
  none, so `stacks/voice/voice-satellite/host-setup.sh` sets it up once per
  machine. `prepare.sh` won't start the satellite without it.
- **Whisper model `base-int8` to start, everywhere** (`VOICE_WHISPER_MODEL`,
  `stacks/fleet.env`). The i3-7100T has two cores. `tiny-int8` is faster and
  less accurate; `small-int8` is likely too slow for these i3s. Nothing here is
  measured yet: the first room settles it (below). percolator also runs the
  household apps, so it's the first to drop to `tiny-int8` if replies lag; its
  `local.env.example` has the line.
- **Piper voice `en_US-lessac-medium`** (`VOICE_PIPER_VOICE`). Any voice from
  Piper's list works; it downloads on first start.
- **Images one release back:** Whisper 3.9.0 and Piper 2.5.4 came out on
  2026-11-17, the day before these were pinned.

## Bringing up a room

On the node, in `/opt/purrbrews/nodes/<node>`, with the speaker and mic plugged in:

1. **Audio, once:**

   ```bash
   sudo /opt/purrbrews/stacks/voice/voice-satellite/host-setup.sh
   ```

   It installs PipeWire, keeps the ops user's session running from boot, and
   lists the speakers and mics it sees. If the defaults aren't the USB ones, run
   it again with `--sink <name> --source <name>`. Then, as barista:
   `pw-play /usr/share/sounds/alsa/Front_Center.wav` (the speaker), and
   `pw-record /tmp/t.wav` for five seconds, Ctrl-C, `pw-play /tmp/t.wav` (the mic).
2. **The apps:** `sudo ./firewall.sh`, then `./compose.sh whisper up -d`,
   `./compose.sh piper up -d`, `./compose.sh voice-satellite up -d`. Whisper and
   Piper download their model on the first start; `docker ps` shows them
   *healthy* once they listen.
3. **In Home Assistant** (Settings → Devices & services):
   - *Add integration* → **Wyoming Protocol** → the node's address, port 10300.
     Again with port 10200.
   - The satellite shows up under *Discovered* as an ESPHome device. If not,
     *Add integration* → **ESPHome** → the node's address, port 6053.
   - Settings → **Voice assistants** → *Add assistant*, named for the room:
     conversation agent Home Assistant, speech-to-text this node's
     faster-whisper, text-to-speech this node's Piper.
   - On the satellite's device page: *Assistant* set to that room's assistant,
     and its wake word.
4. **Prove it:** say the wake word, then "what time is it". The reply should come
   from that room's speaker. Voice assistants → the room's assistant → ⋮ →
   *Debug* shows each step's time; write the speech-to-text times in the runbook.
   If they're over about two seconds, try `tiny-int8` on that node
   (`VOICE_WHISPER_MODEL` in its `.env.local`, then `./compose.sh whisper up -d`).

One room end to end first (sieve, the living room), the other two after.

## Not covered yet

- **Echo cancellation.** A satellite that hears its own speaker can wake itself.
  A speakerphone with built-in echo cancellation avoids it; otherwise PipeWire's
  `echo-cancel` module can, set up once the hardware is known.
- **Monitoring.** Gatus doesn't check the voice ports yet. Each container has a
  healthcheck, so `docker ps` and Komodo show a stuck one.
- **Backups.** Nothing in these apps is worth backing up: models and voices
  download again, and the satellite's few preferences are set again in HA.
