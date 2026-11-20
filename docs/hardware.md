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

Storage: two 128 GB M.2 SATA SSDs, one 256 GB SATA SSD, one 512 GB Intel NVMe,
two 1 TB NVMe, two old 1 TB 2.5" SATA HDDs.

## Who gets what (confirmed 2026-11-17)

The five node names and roles stay; the machines behind them are the ones the
old fleet already used, so nothing is re-cased. What changes is where roastery's
jobs go, one more RAM stick for cellar, and the disks: the ThinkCentres don't
boot from the 128 GB M.2 SATA drives (owner, 2026-11-18), so those stay with
the x360s.

| Node | Machine | Where | RAM | Disks | Role |
|---|---|---|---|---|---|
| `sieve` | ThinkCentre | Living room, wired to the Humax router | 8 GB | 256 GB SATA SSD (2.5" bay) | Network: DNS, DHCP, tunnel, alerting. Voice |
| `percolator` | ThinkCentre | Second room | 16 GB | 1 TB NVMe (OS and `/srv/data`) | Ingress, identity, the household apps. Voice |
| `cellar` | ThinkCentre | Third room | 16 GB (was 8) | 1 TB NVMe (OS, dump store, **the restic repository**) | Backup hub, Komodo, Scrutiny. Voice |
| `mochaPot` | x360 laptop | Wherever its screen is wanted | 8 GB | 128 GB M.2 SATA | Home Assistant, music, secondary DNS, kiosk |
| `grinder` | x360 board | Next to a switch | 16 GB | 512 GB Intel NVMe (M.2) | Automation, LiteLLM, Immich ML, self-tracking |

That uses all eight sticks (8 + 16 + 16 + 8 + 16). The second 128 GB M.2 SATA
drive is the spare. The two old
HDDs stay out of the machines: they are the offline backup copies, written
through the USB dock and kept unplugged (the old fleet had already retired
them from live duty for their age, and Scrutiny flagged one of them).

Disks, as revised on 2026-11-18:

- **The ThinkCentres don't boot from the 128 GB M.2 SATA drives** (owner,
  2026-11-18). mochaPot keeps one; the other is the spare, which matters
  because mochaPot's SanDisk has a history of command timeouts.
- **grinder gets the 512 GB NVMe** in its M.2 slot (owner, 2026-11-18), as in
  the old fleet. Its 2.5" SATA bay stays free for later.
- **sieve runs on the 256 GB SATA SSD** in its 2.5" bay (owner, 2026-11-18). It
  needs the least disk of the five.
- **percolator runs on its 1 TB NVMe alone.** OS and household data share it.

Why this way:

- **The network node is a ThinkCentre** (owner's decision): DNS and DHCP for the
  house should not hang off a USB Ethernet adapter. It needs the least memory
  and disk of the five.
- **cellar gets the second 1 TB NVMe and a second stick** because it now holds
  the restic repository that used to live on roastery. Its old 256 GB system
  disk would not hold a repository for percolator's data.
- **grinder takes the AI jobs** that need no GPU: LiteLLM (a proxy, almost no
  load) and Immich's machine learning on the CPU. percolator already carries
  nineteen apps on two cores.
- **mochaPot keeps the secondary Pi-hole**: its battery rides out a power cut,
  which is when a second resolver earns its place. The cost is that it answers
  through a USB Ethernet adapter; if that proves flaky, the secondary moves to
  cellar (one word in two `node.conf` files, `DNS_SECONDARY` in `fleet.env`,
  and the Gatus check).

## Where roastery's jobs went

| Job | Was | Now | State |
|---|---|---|---|
| Local LLMs (llama-swap, game mode) | roastery's GPU | A cloud model through LiteLLM on grinder, `llm.${DOMAIN}` | Stack written, not yet run. Provider not chosen; any OpenAI-compatible endpoint |
| Immich machine learning | roastery's GPU | grinder's CPU (`stacks/ai/immich-ml`) | Stack written, not yet run. Slow first pass |
| restic repository | roastery's NVMe, SFTP | cellar's 1 TB NVMe, SFTP | **Not built**: [migration plan](migration-plan.md), phase 5 |
| Bootstrap server | A container on roastery | [purrbrews-bootstrap](https://github.com/purrMonster/purrbrews-bootstrap) on americano | Server exists; the fleet's payload is not written (phase 1) |
| Recovery kit builder (flask) | PowerShell on roastery | `recovery/make-flask.sh` and `fill-vault.sh` on americano | Written 2026-11-18; the sticks are the owner's ([recovery-kit.md](recovery-kit.md)) |
| The key every node trusts | `purrbrews-roastery` on roastery | A key on americano, handed out by the bootstrap server | With phase 1 |
| Remote Desktop target | roastery | None | Policy line left in `tailscale/policy.hujson`; remove in phase 10 |

When a GPU is back, the local models return behind the same LiteLLM address, so
no app changes; `deprecated/stacks/roastery/llama-swap` is the starting point.

## Voice (written, not yet brought up)

Each ThinkCentre gets a USB speaker and a conference-room mic and runs
speech-to-text and text-to-speech locally (Whisper and Piper), with Home
Assistant on mochaPot as the brain. That makes sieve, percolator and cellar the
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
5. ~~That a ThinkCentre boots from a 2.5" SATA SSD (sieve's disk).~~ It does
   (owner, 2026-11-18).
6. Both USB Ethernet adapters: ~~that Debian 13 brings them up~~ it does (owner,
   2026-11-18). Still to see, in the rehearsal: that the node's derived MAC
   sticks to them (the x360s have no port of their own).
7. Memory speeds: 7th-gen boards run all of these sticks below their rated
   speed, so mixing 2666 and 3200 costs nothing. Keep the 3200 pair together.
