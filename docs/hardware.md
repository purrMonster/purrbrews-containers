# Hardware plan

Which machine does what after the house move. Written 2026-11-16 from the
hardware the owner listed and from what the old runbook and node READMEs
recorded about each machine. The layout below was proposed by Claude and
confirmed by the owner on 2026-11-17 ([runbook](../runbook.md), 2026-11-16 entry); nothing here
has been checked against the machines themselves.

## What there is

| Machine | CPU | Network | Notes |
|---|---|---|---|
| 3 × Lenovo ThinkCentre mini PC | i3, 7th gen (the old READMEs say M710q, i3-7100T) | built-in Ethernet | One per room; each gets a USB speaker and a conference-room mic |
| HP Pavilion x360, complete laptop | i5, 7th gen (i5-7200U) | **needs a USB Ethernet adapter** | Touchscreen; has a battery |
| HP Pavilion x360, board only | i5, 7th gen | **needs a USB Ethernet adapter** | Motherboard and fan on MDF with standoffs |
| americano (MacBook Air M5) | | Wi-Fi | Not a node: the admin machine, and where the bootstrap server runs |
| roastery (Windows workstation) | | | **Out of the fleet.** Its 3080 died in the move |

Memory: eight 8 GB DDR4 SO-DIMMs (six 2666 MHz, two 3200 MHz), 64 GB in all.

Storage (the owner's count, 2026-11-22; roastery's own 1 TB NVMe not included):
two 1 TB NVMe, one 512 GB NVMe, one 256 GB NVMe, two 256 GB 2.5" SATA SSDs, two
128 GB M.2 SATA SSDs, and the two old 1 TB 2.5" SATA HDDs.

## Who gets what (confirmed 2026-11-17, revised 2026-11-22)

The five node names and roles stay; the machines behind them are the ones the
old fleet already used, so nothing is re-cased. On 2026-11-22 the owner asked
Claude to decide the split by function and by what each failure takes down:
Home Assistant moved from mochaPot to cellar, grinder's disk changed, and the
machines stayed where they were.

| Node | Machine | Network | RAM | Disk | Apps |
|---|---|---|---|---|---|
| `sieve` | ThinkCentre, living room | built-in | 8 GB (1 × 8) | 256 GB SATA SSD (2.5" bay) | **The network:** Unbound, Pi-hole (DNS and DHCP), cloudflared, Traefik for the edge, ntfy, Gatus, NetAlertX. Voice for its room |
| `percolator` | ThinkCentre M710q, second room | built-in | 16 GB (2 × 8; one stick in so far) | **256 GB EVM NVMe** (OS and `/srv/data`) (2026-11-23) | **Ingress and sign-in:** Traefik, CrowdSec, the mail relay, LLDAP, Authelia. **The household apps:** Radicale, OpenCloud, Vaultwarden, Paperless, Mealie, Vikunja, meowGram, Actual, FreshRSS, Homepage, purrCafe. Voice for its room |
| `cellar` | ThinkCentre, third room | built-in | 16 GB (2 × 8) | 256 GB SATA SSD (OS, 2.5" bay) + 1 TB NVMe (`/srv`: dump store, **the restic repository**) | **Backups** (the hub and the repository), Komodo, the Scrutiny hub, persianPerch, Samba. **Home Assistant.** Voice for its room |
| `mochaPot` | x360 laptop, at the wall screen | USB adapter | 8 GB (1 × 8) | 128 GB M.2 SATA (the SanDisk) | The second Pi-hole (DNS only), Music Assistant, the kiosk |
| `grinder` | x360 board, next to a switch | USB adapter | 16 GB (2 × 8) | **1 TB WD SN530 NVMe** (M.2) (2026-11-23) | **Photos: Immich** (2026-11-23). Automation and AI: n8n, LiteLLM, Immich ML, the embedding worker and its Postgres, Open WebUI, Karakeep, FitTrackee, Traccar, ESPHome, speedtest-tracker, pourOver |

Every node also runs the Komodo agent, the Scrutiny collector and Traefik (on
sieve and percolator, their own edge and ingress Traefiks), and backs up to
cellar. Memory uses all eight sticks (8 + 16 + 16 + 8 + 16); the 3200 MHz pair
goes into one of the 16 GB nodes.

Off the fleet:

| Disk | Where |
|---|---|
| 512 GB NVMe | Kept for roastery, when it's back (owner, 2026-11-22), beside its own 1 TB |
| 128 GB M.2 SATA | **Spare** for mochaPot, whose SanDisk has a history of command timeouts. The ThinkCentres don't boot from it |
| The two old 1 TB HDDs | The offline backup copies, through the USB dock, kept unplugged. Old, and Scrutiny flagged one |

There is no spare for the two 1 TB NVMe drives. If one fails, the 512 GB can
stand in until roastery is back, or a new drive is bought. Nor, since cellar
took the second 256 GB SATA SSD for its OS (2026-11-23), is there a spare a
ThinkCentre can boot from: a cheap 2.5" SATA SSD is worth buying.

### Why this split

The rule is the same one that put the network on a ThinkCentre: **what the
house can't do without goes on built-in Ethernet, on a node that isn't
percolator.** Then each node's failure takes down one kind of thing.

- **sieve is the network and nothing else heavy.** DNS, DHCP, the tunnel and
  the alerts. It watches the others, so it can't share their failures. Its
  voice apps are small and only its own room's.
- **percolator holds everything behind sign-in.** The household apps go down
  with Authelia anyway, so they share its machine; splitting them across nodes
  would add failures without removing one.
- **Home Assistant goes to cellar** (it was on mochaPot). Lights, sensors and
  the voice assistants are the house's own infrastructure, so: built-in
  Ethernet (mochaPot answers through a USB adapter, and it's the laptop people
  move); not percolator, so the house keeps working when sign-in or a household
  app update breaks; not grinder, which is meant to be cheap to lose; not sieve,
  which should stay small and predictable for DNS. cellar is the quietest
  machine: busy only at night for backups, rarely changed, 16 GB.
- **mochaPot keeps the second resolver, Music Assistant and the screen.** Its
  battery rides out a power cut, which is when a second resolver earns its
  place; music is not something the house depends on. The wall screen now shows
  Home Assistant on cellar, straight to its port (`http://192.168.1.12:8123`),
  so it needs neither DNS nor Traefik. If the USB adapter proves flaky, the
  secondary resolver moves to cellar (one word in two `node.conf` files,
  `DNS_SECONDARY` in `fleet.env`, and the Gatus check).
- **grinder holds what can be shed, and Immich.** Immich moved here on
  2026-11-23 (owner), when the disks stayed as installed: the 1 TB NVMe went
  into the x360 and percolator kept the 256 GB, so the photos follow the big
  disk and sit beside their machine learning. It is the one household app
  that goes down with grinder; everything else on it can be shed.

Home Assistant on a ThinkCentre loses one thing: the laptop's built-in
Bluetooth. Whether the ThinkCentres have Bluetooth is not known yet
(`bluetoothctl list` on cellar, migration plan phase 7). If not, and something
needs it, a USB Bluetooth adapter or an ESPHome Bluetooth proxy covers it.

### When a node goes down

| Down | Stops | Keeps working |
|---|---|---|
| sieve | New DHCP leases (devices keep theirs until they expire); every public hostname (the tunnel); alerts and Gatus; the living room's voice | Name resolution, through mochaPot's Pi-hole (slowly: clients wait out the primary first). Everything else by address on the LAN; Home Assistant |
| percolator | Sign-in, and with it every page behind Authelia on any node (on grinder, Immich's *Login with Authelia*; its own passwords still work); the household apps; the second room's voice | Home Assistant (its local account; and the kiosk), music, DNS and DHCP, alerts, backups. Komodo and Scrutiny on their own ports |
| cellar | Home Assistant and the voice assistants in every room; the kiosk's dashboard; backups (the nightly runs fail and say so); Komodo, Scrutiny, persianPerch | Sign-in and the household apps, DNS and DHCP, the tunnel, alerts, music |
| mochaPot | The second resolver, music, the wall screen | Everything else |
| grinder | Immich (photos and phone backup), n8n's automations, the AI chat and LiteLLM, Karakeep, FitTrackee, Traccar, the ESPHome dashboard (devices keep working with Home Assistant), speed tests | Everything else |
| Power cut | Everything but mochaPot, unless the router and switches are on a UPS | mochaPot's resolver, for whatever still has power |

cellar now carries two things the house notices (Home Assistant and backups),
which is the cost of this layout. Backups tolerate a missed night; Home
Assistant is the one to watch, and Gatus on sieve checks it.

### Memory, roughly

Estimates for planning, from the apps' usual footprints; Komodo shows the real
numbers once they run. Swap is on every node.

| Node | RAM | Expected use | Heaviest |
|---|---|---|---|
| sieve | 8 GB | 2–3 GB | Whisper's model, NetAlertX |
| percolator | 16 GB (8 until the second stick) | 7–9 GB | Paperless, OpenCloud, Whisper |
| cellar | 16 GB | 5–7 GB, more during a prune | Komodo and its database, Home Assistant and its Postgres, restic at night |
| mochaPot | 8 GB | about 2 GB | Chromium for the kiosk, Music Assistant |
| grinder | 16 GB | 10–13 GB | Immich and its Postgres, Immich ML with its models loaded, Open WebUI, the embedding worker, Karakeep's Chrome |

All five CPUs are two-core 7th-gen chips, which matters more than memory:
percolator's Whisper is the model to size with care (docs/voice.md), and
Immich's and Paperless's first imports are best left to run overnight.

### Disks, as revised

- **The ThinkCentres don't boot from the 128 GB M.2 SATA drives** (owner,
  2026-11-18), so those stay with the x360s: mochaPot's, and the spare.
- **grinder runs on a 1 TB WD SN530 NVMe** (as installed, owner 2026-11-23;
  the 2026-11-22 plan gave it the 256 GB). It holds Immich's library, the one
  thing in the fleet that grows by the gigabyte. Its 2.5" bay stays free.
- **sieve runs on a 256 GB SATA SSD** in its 2.5" bay (owner, 2026-11-18).
- **percolator runs on the 256 GB EVM NVMe alone** (as installed, owner
  2026-11-23; cellar's old system disk). OS and household data share it: about
  229 GB, with OpenCloud's files the thing to watch now that Immich is on
  grinder. The old Seagate 1 TB HDD is in its bay for now, holding an
  installer image; it is still meant for the offline copies.
- **cellar gets the second 1 TB NVMe and a second stick** because it holds the
  restic repository that used to live on roastery. Debian went onto the second
  256 GB SATA SSD in its bay (2026-11-23) and stayed there: the NVMe is all
  `/srv`, so a full repository can't stop the OS and a reinstall never touches
  the backups.


## Checked on the machines (2026-11-23)

From the owner's survey script (pasted in chat), Debian 13, kernel
6.12.117+deb13-amd64, UEFI, AVX on both.

| | percolator | grinder |
|---|---|---|
| Machine | Lenovo ThinkCentre M710q, i3-7100T | HP Pavilion x360 14-ba0xx, i5-7200U |
| Memory | 1 × 8 GB SK Hynix `HMAA1GS6CJR6N-XN` at 2400 (ChannelA); ChannelB empty | 2 × 8 GB: SK Hynix `HMA81GS6AFR8N-UH` + G.Skill `F4-3200C22-8GRS`, both at 2133 |
| Boot disk | 256 GB EVM NVMe (`EVMNV/256GB`): 1 % used, 85 h, 0 media errors | 1 TB WD PC SN530: 9 % used, 11,770 h, 0 media errors |
| Other disk | Seagate ST1000LM035 1 TB HDD (2.5" bay), holding an installer image; SMART not read | — |
| Layout | 976 MB EFI, 229.6 GB ext4 `/`, 7.9 GB swap; `/srv` not separate | 976 MB EFI, 937 GB ext4 `/`, 15.9 GB swap; `/srv` not separate |
| Network | Intel I219-LM `enp0s31f6`, `.163` by DHCP; MAC reported is locally administered (`2a:3b:…`): check `ethtool -P`. Wi-Fi and Bluetooth present, unused | USB adapter `enxa0cec8fcd32a`, up at boot, `.119` by DHCP. No Wi-Fi or Bluetooth device |
| SSH | active; `passwordauthentication yes` | same |

What this adds to the list below: the old files were right that cellar had a
256 GB NVMe (item 1), and it is now percolator's. This ThinkCentre has
Bluetooth (item 8, Intel `8087:0a2b`, `hci0`). grinder's two sticks are a
mixed pair, one of them a 3200 (item 7); both run at 2133, the CPU's limit.

## Where roastery's jobs went

| Job | Was | Now | State |
|---|---|---|---|
| Local LLMs (llama-swap, game mode) | roastery's GPU | A cloud model through LiteLLM on grinder, `llm.${DOMAIN}` | Stack written, not yet run. Provider not chosen; any OpenAI-compatible endpoint |
| Immich machine learning | roastery's GPU | grinder's CPU (`stacks/ai/immich-ml`) | Stack written, not yet run. Slow first pass |
| restic repository | roastery's NVMe, SFTP | cellar's 1 TB NVMe, SFTP | **Not built**: [migration plan](migration-plan.md), phase 4 |
| Bootstrap server | A container on roastery | [purrbrews-bootstrap](https://github.com/purrMonster/purrbrews-bootstrap) on americano | Server exists; the fleet's payload is not written (phase 1) |
| Recovery kit builder (flask) | PowerShell on roastery | `recovery/make-flask.sh` and `fill-vault.sh` on americano | Written 2026-11-18; the sticks are the owner's ([recovery-kit.md](recovery-kit.md)) |
| The key every node trusts | `purrbrews-roastery` on roastery | A key on americano, handed out by the bootstrap server | With phase 1 |
| Remote Desktop target | roastery | None | Policy line left in `tailscale/policy.hujson`; remove in phase 10 |

When a GPU is back, the local models return behind the same LiteLLM address, so
no app changes; `deprecated/stacks/roastery/llama-swap` is the starting point.

## Voice (written, not yet brought up)

Each ThinkCentre gets a USB speaker and a conference-room mic and runs
speech-to-text and text-to-speech locally (Whisper and Piper), with Home
Assistant on cellar as the brain. That makes sieve, percolator and cellar the
three voice machines, and all three run both engines, percolator included
(owner, 2026-11-17). The stack is `stacks/voice/` ([voice.md](voice.md));
bringing it up is phase 9 of the [migration plan](migration-plan.md).
percolator is the busiest machine, so its Whisper model is the one to size with
care.

The living-room screen: the owner would rather have a tablet on a dock (or an
ESP32 screen) there than the laptop. Until one exists, the kiosk stays on
mochaPot's own touchscreen.

## The network

| | |
|---|---|
| Router | Humax, from Tata Play Fiber. Its DHCP can be turned off |
| LAN | `192.168.1.0/24` (the old house was `192.168.0.0/24`) |
| Gateway | `192.168.1.1`, the Humax router (owner, 2026-11-18). Its DHCP is off since 2026-11-19: sieve's Pi-hole hands out `.50`–`.250` |
| americano | `192.168.1.15`, set by hand on the Mac (outside every DHCP pool): the nodes reach purrbrews-bootstrap there |
| Internet | Tata fiber, with IPv6 (the old fleet was on ACT: IPv4 only, behind CGNAT). The nodes take no IPv6 address (the payload sets `ipv6.method disabled`), so nothing on them is reachable over IPv6; household devices are, behind the Humax's IPv6 firewall. The router's IPv6 DNS is off, so devices resolve through the Pi-holes (owner, 2026-11-19) |
| Nodes | `.10` sieve, `.11` percolator, `.12` cellar, `.13` mochaPot, `.14` grinder (the old last octets) |
| DHCP pool | `.50` to `.250`, from sieve's Pi-hole once the router's DHCP is off |
| Docker `proxy` network | `172.31.10.0/24` sieve, `172.30.0.0/24` percolator, `172.30.12.0/24` cellar, `172.30.13.0/24` mochaPot, `172.30.14.0/24` grinder |

## To check on the machines before phase 1

1. `lsblk -d -o NAME,SIZE,MODEL` on each: the old files disagree with the list
   above in two places (sieve "a 240 GB 2.5" SATA SSD", cellar "a 256 GB NVMe").
   The table follows the owner's list.
2. ~~That a ThinkCentre boots from an M.2 SATA stick.~~ It doesn't (owner,
   2026-11-18); the disks above follow from that.
3. ~~That each x360 has two memory slots (grinder's 16 GB needs both).~~ Two
   each (owner, 2026-11-18). grinder's board has a 2.5" SATA bay as its second
   drive slot (owner, 2026-11-18).
4. mochaPot's 128 GB SanDisk has a history of command timeouts (Scrutiny, old
   runbook 2026-09-26 and 2026-09-30). The other 128 GB drive is its spare.
8. Bluetooth on the ThinkCentres (for Home Assistant on cellar): `bluetoothctl
   list`. None is fine unless something in the house needs it.
5. ~~That a ThinkCentre boots from a 2.5" SATA SSD (sieve's disk).~~ It does
   (owner, 2026-11-18).
6. Both USB Ethernet adapters: ~~that Debian 13 brings them up~~ it does (owner,
   2026-11-18). Still to see, in the rehearsal: that the node's derived MAC
   sticks to them (the x360s have no port of their own).
7. Memory speeds: 7th-gen boards run all of these sticks below their rated
   speed, so mixing 2666 and 3200 costs nothing. Keep the 3200 pair together.
