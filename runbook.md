# PurrBrews Runbook

Dated design decisions for this repo, newest first. Each entry records *why*, so
changes can be made later without re-deriving the reasoning.

## Backlog / open items

- [x] Confirm Secret scanning + Push protection are enabled on the public GitHub repo (repo itself already created, pushed, `origin` set). Confirmed in the repo's settings (owner, 2026-09-29)
- [x] Workstation: DHCP reservation, `bootstrap/data/` (settings + `authorized_keys`), `docker compose up -d --build`, firewall rule for 8443 Done: `purrbrews-bootstrap` healthy on roastery (192.168.0.15), inbound rule for 8443 enabled (checked 2026-09-29)
- [ ] First real node through `bootstrap.sh`, at the console (the network step has not yet run on real hardware) All five nodes run; whether the first went through `bootstrap.sh` at the console is for the owner to confirm (owner)
- [x] Add stacks node by node, each with its own `stacks/<node>/README.md` — sieve, percolator, cellar, mochaPot and grinder are all in
- [x] Pi-hole static leases from `purrbrews-mac.sh`: automated by `stacks/sieve/setup-secrets.sh` (2026-09-15)
- [x] sieve: Cloudflare DNS token, tunnel + `ntfy.${DOMAIN}` route, healthchecks.io check, then the bring-up in `stacks/sieve/README.md` Done: all running; the ntfy route and healthchecks.io proven 2026-09-29 (entry below)
- [x] sieve: prove both alert paths with a deliberate break (stop NetAlertX → ntfy; stop ntfy → ntfy.sh) Done 2026-09-29, both delivered; ntfy.sh titles fixed the same day, retest in that entry
- [x] sieve: router DNS → 192.168.0.10, then hand DHCP to Pi-hole (router DHCP left configured but off) Done: Pi-hole's DHCP active with the router 192.168.0.1 as gateway, 23 leases; roastery gets DNS 192.168.0.10 and .13 (checked 2026-09-29)
- [x] percolator: Authelia's 9091 published (UFW: `FORWARD_AUTH_CLIENTS`), session domain `${DOMAIN}`, admin-only rules for `pihole`, `gatus`, `netalertx`, `traefik-sieve` — done in percolator's stack (2026-09-16)
- [x] percolator: Cloudflare token, then the bring-up in `stacks/percolator/README.md`; `sudo ./firewall.sh` Done: Traefik, Authelia, CrowdSec and the apps up 3 days with valid certificates; `ufw-docker` installed; `FORWARD_AUTH_CLIENTS` on the node includes roastery (checked 2026-09-29). `ufw status` itself needs sudo, not read
- [x] First ForwardAuth round trip from sieve's Traefik to Authelia on real hardware (sandbox-tested with real Authelia 2026-09-16) Done 2026-09-29: `gatus` (sieve's Traefik) and `homepage` both answer 302 to Authelia with a valid certificate
- [x] cellar's, mochaPot's and grinder's stacks added, each with its own Traefik (2026-09-16)
- [x] Register cellar, mochaPot and grinder with percolator: `FORWARD_AUTH_CLIENTS` and `admin_hosts` extended, cellar's Traefik built for real (2026-09-16, full fleet repass)
- [x] Migrate Komodo Periphery + Scrutiny collector fleet-wide (sieve, percolator, mochaPot, grinder, roastery) — built from cellar's own service blocks, since `stacks/_templates/komodo-periphery/` never actually landed in the repo (2026-09-16)
- [x] `firewall.sh` for cellar, mochaPot and grinder — none had one before; every published port on them was reachable from the whole LAN with no `ufw route allow` gate (Docker's iptables DNAT bypasses plain `ufw`) (2026-09-16, full fleet repass)
- [x] Confirm Komodo Periphery's cross-host auth (pinning Core's public key alone) on a real bring-up — only reasoned about and sandbox-built, not tested cross-host; may need its own passkey/API key from Core's UI Done 2026-09-29: every node's Periphery logs "Logged in to Komodo Core 192.168.0.12:9120"; grinder reconnected on its own after the 2026-09-29 cable test
- [x] Confirm each node's `DISK_DEVICE` (and `DISK_DEVICE_2` on percolator and cellar) against real hardware (`lsblk -d -o NAME,TYPE,SIZE,MODEL`); these were the per-node `*_DISK_DEVICE*` keys until 2026-09-26 Done 2026-09-29: all seven match `lsblk`, every collector reporting in Scrutiny
- [ ] cellar's Samba: `smb/docker-compose.yml` exists but nothing uses it and ufw-docker keeps 445 closed. Decide on shares and permissions, pin the image, then uncomment the rule in `smb/firewall`
- [x] Wire cellar's restic sources to percolator's, sieve's and mochaPot's actual dumps and data: replaced by each node's own `backup` files (2026-09-27)
- [ ] Backups to roastery, cellar as the dump store, second copy of everything on Google Drive (decided 2026-09-26; design in the 2026-09-27 entries). Scripts written 2026-09-27; every node's backups on since 2026-09-28; Drive set up 2026-09-29, first upload running. Restore tests from roastery and from Drive passed 2026-09-29; the first full night clean 2026-09-30. Next: the Drive client and `rclone.conf` into the vault, stick B, and the first monthly verify on 2026-10-01 (2026-09-27 wiring entry). Replaces the old "enable cellar's roastery mirror and Google Drive sync" item
- [ ] Replace cellar's old disk (ST1000LM035, 5–8 years old) once it's only the dump store; the SanDisk on mochaPot is the same age. Superseded 2026-09-28: it's out of use on cellar and becomes the offline copy after a long self-test (2026-09-28 flask entry)
- [x] roastery: `immich-machine-learning` at Immich's version, Windows Firewall 3003 scoped to percolator. Verified 2026-09-29 on roastery (Claude, owner approved): container `immich-machine-learning:v3.2.1-cuda` matches percolator's `immich-server:v3.2.1`; rule `immich-ml (percolator only)` enabled, remote address `192.168.0.11` only
- [x] Postgres dump job for percolator's databases (Nextcloud, Immich, Paperless): `pg` lines in their `backup` files (2026-09-27)
- [ ] Remaining node: roastery itself joining the fleet; then archive purrBrews-infra
- [ ] Gatus: add app checks as stacks land (node pings for percolator, cellar, mochaPot and grinder enabled 2026-09-29)
- [ ] Optional: paste `purrbrews-mac.sh list --format pihole` into Pi-hole's static DHCP list
- [x] Roll out the 2026-09-26 cleanup on every node: every node pulled it (2026-09-26, per the owner)
- [ ] Work through the 2026-09-26 live-check plan (entry below)
- [ ] Setup keeps a node's existing values, so a changed default in `local.env.example` never reaches a node that's already set up (how percolator's `FORWARD_AUTH_CLIENTS` went stale). Have setup-secrets list keys whose value differs from the example, so the drift is at least visible
- [ ] Decide: keep barista in the `docker` group (added 2026-09-26; root without a password) or take it out again once the live-check fixes are done
- [ ] cellar: confirm Komodo still logs in after `KOMODO_DISABLE_USER_REGISTRATION` went to `true` Core has `KOMODO_DISABLE_USER_REGISTRATION=true` and `KOMODO_LOCAL_AUTH=true` (checked 2026-09-29); the login itself is for the owner (owner)
- [x] Pin n8n (`latest`), Open WebUI (`main`) and Karakeep (`release`) Done 2026-09-29: n8n `2.39.7` and Karakeep `0.33.2`, each the same digest as what was running; Open WebUI by digest (its `main` build isn't the v0.11.3 release)
- [ ] meowGram: route and Authelia client prepared on branch `meowgram-sso` (2026-10-04 entry); merge and bring up, then the open items in `stacks/roastery/meowgram/README.md` (backups, web build, the audience check)
- [ ] Open WebUI → roastery's LLMs (llama-swap since 2026-10-07; grinder's `OLLAMA_BASE_URL` still points at the old `:11434`): needs machine-to-machine auth that keeps Authelia in front; options in the 2026-10-07 entry, none chosen
- [ ] Karakeep: `NEXTAUTH_URL` is the direct-port URL while the route is `karakeep.${DOMAIN}`; check the phone share sheet signs in through the hostname
- [x] Remote access over Tailscale: rolled out and checked from outside the house (2026-09-28; 2026-09-27 entry below)
- [ ] roastery after the 2026-09-27 power cut: UPS install, the old HDD, NVMe into Scrutiny (2026-09-27 power-cut entry below)
- [ ] Phone on the tailnet (only the Mac has joined so far)
- [ ] Tunnel from Git: two-factor in Authelia first, then the switch in `stacks/sieve/cloudflared/README.md` (2026-09-28 entry below)
- [ ] Apps over the tailnet: roll out in the order in the 2026-09-28 entry below
- [ ] Bot identity for Claude's commits and pull requests: owner picks bot account or GitHub App, then the setup in the 2026-09-28 entry below
- [ ] roastery: `init\roastery-init.ps1` on the rebuilt PC, elevated (owner), after the repository is back from Drive; then the follow-ups it prints for the nodes, ticked here with what was seen (2026-10-08 init entry)

---

## 2026-10-09 — Debian verification and focused cleanup commits

The owner authorized tests, Debian WSL dependencies and individual local commits,
then requested another codebase review. Installed Python/pytest, Git, restic,
sqlite3, rclone, OpenSSL and ShellCheck in the newly installed Debian environment.
The earlier Windows pytest attempt could not start because pytest was absent.
Debian installation completed; its systemd-binfmt package trigger reported a WSL
failure, which did not prevent the test tools from running and was not changed.

Evidence (2026-10-09): the final non-root Debian suite passed 75 tests with four
skips. Three root-only local backup integration tests passed separately; Linux
PowerShell rendering parity remains skipped because pwsh is absent. Native
Windows Compose regression checks passed. All eight resolved Compose models
matched the archived originals using fixture values and no running containers.
Active PowerShell scripts parsed; ShellCheck found no errors and one cross-file
CURRENT_STEP warning (the sourced init script's warn/die functions use it).

The second review added preview-safe wrapper dispatch and Windows stale-render
checks, with regression tests. It also fixed Windows test collection and explicit
Bash resolution. The repeat suite passed after these changes. No fleet nodes,
backup destinations or running application services were changed; no pushes.
The test guide is tests/README.md; detailed limitations are in docs/cleanup-review.md.

Commits on codex/code-sanitization:
- 60c9fa8: shared Linux service definitions and archived originals.
- c77f58b: Compose helper fixes and regression checks.
- fd9f248: shared-config coverage, portable test harness and test guide.
- be1f1b4: generated-output and archive analysis exclusions.
- Documentation and this handoff: docs: record verified cleanup and deployment prerequisites.

The earlier Repository structure review entry and Claude integration files remain
uncommitted. Git had no configured identity; commits used the established identity
from this repository's recent history, without changing global configuration.
Graphify outputs stay local and retain the audit of extraction limitations.
Next: owner-authorized deployment and live alert-path checks; optionally install
Linux pwsh for rendering parity, confirm external groom-record deployment, and
resolve the recorded Open WebUI authentication decision separately.
Undo source changes with ordinary inverse commits, using Deprecated/README.md
for original Compose paths; do not rewrite history or discard earlier edits.

---

## 2026-10-09 — Shared service refactor and command usability

Extended the cleanup on `codex/code-sanitization` into a runtime-source refactor,
following the owner's expanded request. Eight original Linux Compose files were
moved to `Deprecated/2026-10-09/stacks/`; their active replacements extend two
`stacks/_shared/` definitions. Per-node keys, disk devices, percolator's second
disk and mochaPot's collector workaround stay in the node files. Image versions,
service names, environment settings and restart policies were carried over.

PowerShell Compose now supports `--help` and `--list` without Docker or secrets.
The Linux wrapper rejects invalid app targets before preparation and only
migrates keys/creates its network for up/create/start/restart/run/watch/scale. Inspection,
pull and teardown avoid those incidental changes. Existing source checks now
follow shared environment references and image pins, exclude archived/generated
sources from active scans, and retain archived files in the credential scan.
Both wrappers now skip global option values when identifying the command, so
`--profile` values cannot suppress preflight or accidentally reverse app order.
The stack guide records dynamic file discovery and the full-checkout requirement.

Second pass evidence: source/diff review on 2026-10-09 covered the eight leaf
files, both shared definitions, command dispatch and raw-Compose consumers.
No tests or operational scripts ran; no runtime equivalence or deployment is
claimed. No dependencies installed, node/remote changes, commits or pushes.
Prior owner-approved working-tree changes remain. Next: authorize offline tests
and a resolved-Compose comparison before rollout; confirm external groom-record
usage separately. Graphify is refreshed separately in the local output directory.

Undo: use `Deprecated/README.md` to move the originals back without overwriting
replacements, then reverse this pass's helper, check and documentation edits.
The earlier cleanup entry below describes the first, documentation-only stage.

---

## 2026-10-09 — Workspace cleanup on codex/code-sanitization

Reviewed the tracked file inventory, identical-file groups, node app manifests,
script references, dynamic init dispatch, backup unit discovery, Python imports
and local Markdown file targets. Evidence: local source inspection on 2026-10-09;
all six node app lists matched their Compose folders, and the tracked Markdown
file-target scan found no missing files. The existing Graphify map was used for
navigation, then findings were checked against the source.

Corrected stale backup status, Windows init and sleep-policy descriptions; added
a guide to the shared helpers in stacks/README.md and a cleanup review in
`docs/cleanup-review.md`. Added `Deprecated/README.md` as the archive index and
ignored generated `graphify-out/` files in Git. Those outputs remain on disk;
the graph snapshot predates these documentation edits. No runtime files could
be confidently retired, so none were moved or deleted. Runtime code and service
configuration are unchanged. Earlier runbook and Claude integration edits remain.

Tests were not run, as requested. No dependencies were installed, no nodes or
remotes were accessed, and no commits or pushes were made. Next: owner decisions
on the external groom-record integration, possible shared Compose fragments and
Graphify availability for Claude hooks; evidence is in the cleanup review.
Undo: reverse only this cleanup's documentation and ignore-rule edits, preserving
the earlier runbook and Claude changes. No runtime paths need restoring.

---

## 2026-10-09 — Graphify repository map

Built the Graphify knowledge graph for the repository, including the existing working-tree changes in `runbook.md`, `.claude/CLAUDE.md` and `CLAUDE.md`. Detection found 198 supported files (87 code, 111 documents; about 116,459 words); 41 sensitive files were excluded. Outputs are in `graphify-out/` (`graph.html`, `GRAPH_REPORT.md`, `graph.json`). The graph has 748 nodes, 1,088 edges and 114 labeled communities.

Integrity check: 83 dangling-endpoint edges, one self-loop, and endpoint-pair collapses (8 directed, 12 undirected); review the report before relying on those relationships. The SQL source yielded no symbols because `tree_sitter_sql` was unavailable. Semantic extraction token usage was not exposed by the agent tool, so Graphify recorded zero token counters rather than measured usage.

No tests ran; no nodes or remotes were accessed or changed. No commits or pushes. Next: review the report and health findings, then use Graphify queries as needed. Undo: remove this entry and `graphify-out/`.

---

## 2026-10-08 — `init/roastery-init.ps1`: roastery gets an init

The owner: every Debian node has `purrbrews-init.sh`, roastery had nothing, and
the 2026-10-07 wipe showed what that costs. Its setup was spread over three
scripts, two READMEs and a handful of clicks (the bootstrap firewall rule, the
immich-ml rule, Traefik's scheduled task, power), and the clicks went with the
wipe.

**What it is:** one PowerShell script, run elevated from the repo, with named
steps in the order of roastery's README ("Rebuilding roastery"): `hostname`,
`network`, `power`, `prereqs`, `ssh_key`, `remote_access`, `backup_target`,
`apps`, `traefik`, `game_mode`, `bootstrap`. It calls the existing scripts
(`remote-access\setup.ps1`, `backup-target\setup.ps1`, `setup-secrets.ps1`,
`compose.ps1`, `game-mode\install.ps1`) and does the hand-made parts itself.
`-Only`/`-Skip`/`-ListSteps`/`-Yes` like the bash init; logged to
`C:\ProgramData\purrbrews\logs`.

**Choices worth remembering:**

- **A step that can't finish yet blocks, it doesn't abort.** It says what it
  needs (no repository, no `traefik.exe`, Docker not started) and the run goes
  on; the summary lists blocked steps, warnings and node-side follow-ups, and
  `-Only <step>` resumes. Nothing it does on roastery is destructive, so the
  rest is worth having.
- **Repository first, nodes after** (2026-10-07): `backup_target` refuses while
  `C:\purrbrews\restic` has no `config` file and points at RECOVERY.md part B.
  `-AllowEmptyRepository` is the deliberate way past it.
- **It never writes `bootstrap\data\authorized_keys`.** That file is the
  fleet's whole SSH trust list, so a guessed one (say, only roastery's new key)
  would revoke the Mac from every node within the hour. It stops and says how
  to rebuild it from a node's managed block, without the old roastery key.
  The bootstrap step is last and asks first: down, the nodes' key sync just
  says unreachable; up with a new TLS key, it fails on every node until each
  re-pins (the command is printed).
- **Traefik's task is in the repo now** (a 2026-10-07 proposal): at boot, as
  SYSTEM, `ExecutionTimeLimit` zero, three restarts; and the leftover
  `config\dynamic\ollama.yml` is deleted if it's there.
- **Power: never sleep on AC, hibernation off**, the 2026-09-29 decision, until
  wake-on-demand exists. roastery's README said "sleeps between uses"; fixed.
- **Not done by the script:** downloading `traefik.exe`, the restore itself,
  meowGram and the kitten (their own repos), anything on a node.

**Checked** (in a Linux session, not on roastery): every `.ps1` parses under
PowerShell 7.4 and is ASCII; the steps run with Windows cmdlets stubbed out
(the network step's warnings, and the blocked paths of `backup_target`, `traefik`,
`apps` and `bootstrap`, each with its message); a `RoasteryInit` test class pins
the order, the repository guard, that `authorized_keys` is never written, the
task's time limit and the three firewall rules' scopes. `python3 -m unittest
discover -s tests`: 75 tests, OK (11 skipped). **Not checked:** Windows
PowerShell 5.1 and any real step on Windows.

**Undo:** revert the commit; the script changes nothing until someone runs it.
On roastery, what it made has names: firewall rules `purrbrews-bootstrap`,
`purrbrews-immich-ml`, `purrbrews-traefik`, the `traefik` task, and the power
settings (`powercfg /change standby-timeout-ac <minutes>`).

---

## 2026-09-28 — A bot identity for Claude's commits and pull requests

The owner wants the changes Claude sessions make to come from a bot, not from
the owner's own identity. Today they're committed as the owner (the global git
identity on roastery) and pushed with the owner's SSH key, and the owner opens
each PR from the link.

**Recommended: a machine account** (e.g. `purrbrews-bot`), over a GitHub App.

- A GitHub App gets the real `[bot]` badge, but pushing as an app needs an
  installation token minted from its private key every hour. That's a script in
  the path of every push, and one more thing to break.
- GitHub allows one free machine account per person; with Write access and
  branch protection it can only propose changes.
- **Not decided yet:** the owner hasn't picked between the two.

**The owner's part** (account creation is never Claude's):

- [ ] Create the bot account, two-factor on, with an email the owner controls
- [ ] Repo → *Settings → Collaborators*: invite it with **Write**; accept as the bot
- [ ] Repo → *Settings → Branches*: protect `main`, require a pull request, so the
  bot can propose and only the owner merges
- [ ] Add the bot's SSH public key (from the step below) to the bot account

**On roastery (Claude, once the account exists):**

- [ ] A dedicated SSH key for the bot. Its private half never leaves roastery, and
  it's never in the repo.
- [ ] An SSH host alias (`github-bot`) in `~/.ssh/config`, so the bot's pushes use
  its key and the owner's pushes keep using the owner's
- [ ] Claude's worktrees (only) set `user.name`/`user.email` to the bot, with the
  email being its GitHub noreply address (`<id>+<bot>@users.noreply.github.com`),
  so no real address or domain enters history. The owner's global identity stays
  as it is.
- [ ] GitHub CLI logged in as the bot, its token in Windows Credential Manager (not
  a file), so the bot opens the PR itself
- [ ] Pre-push checks as now (no domain, MAC, auth key or old emails in the
  outgoing commits), plus: every outgoing commit is authored by the bot
- [ ] flask: build the two sticks and the paper, `make-flask.ps1` and `RECOVERY.md` first ([docs/flask.md](docs/flask.md); 2026-09-28 flask entry below). 2026-09-30: A built and booted twice; next, rebuild with the boot injection and test it offline (in a VM on roastery, then one real PC), then B, the vault's Drive entries and the paper
- [ ] Offline copy of the restic repository: the old Seagate in a USB enclosure, synced monthly; `offline-sync.ps1` still to write (2026-09-28 flask entry)
- [ ] roastery: move the repository off C: to a second NVMe (2026-09-28 flask entry)
- [x] mochaPot's SanDisk runs at 67 °C: check its airflow. **Not real heat: the disk runs at 36 °C.** Checked 2026-09-30 with smartctl inside `scrutiny-collector` (the host has no smartctl): attribute 194 raw is `36 (Min/Max 14/67)`, SCT status says current 36 °C, but device statistics report "Current Temperature 67", identical to its "Highest Temperature" and flat for days. That stuck value is what Scrutiny shows. Treat Scrutiny's temperature for this disk as unreliable; `smartctl -A` is the source of truth. (It's an M.2 SATA drive, not NVMe, in a slot under the board with no heatsink; the disk is nearly idle and the CPU at 47 °C, so nothing to fix.) Power-on hours confirmed at 18,975. Scrutiny fixed the same day: `smartctl --xall` (Scrutiny's default) reads the stuck log and gives 67 °C and 668 hours, which was also the "28 days"; `--all` gives 36 °C and 18,975 hours. mochaPot's collector now uses `--all` for this disk (`scrutiny-collector/collector.yaml`)
- [ ] Still floating: Unbound (`main`) and Samba (`latest`), both on purpose (their compose files say why). Home Assistant pinned to 2026.10.0 and ESPHome to 2026.9.1 on branch `hardening-2026-10-08`, the versions `stable` resolved to that day (same digests); `tests/` now fails on any other floating tag. Before merging, check the running versions: `docker inspect homeassistant esphome --format '{{.Config.Image}}'` and HA's About page; if a node already runs something newer, bump the pin rather than go back (HA's migrations only go forward)
- [ ] Node checkouts: percolator has an untracked `.env.local.bak-20260926` (secrets; delete once sure), mochaPot a stray `bootstrap/--no-check-certificate` file and `tests/test_network_gateway.sh` (owner)
- [ ] Home Assistant: bring the lights and devices in. The backbone runs on mochaPot (Traefik, OIDC, Postgres), nothing is paired yet. Integrations and pairing first; areas and automations once the home layout is final (owner, 2026-09-30)
- [ ] ESP32 sensors and voice speakers: build them with ESPHome (grinder), and a voice pipeline in Home Assistant's Assist with roastery's LLMs as the conversation backend (llama-swap since 2026-10-07: an OpenAI-compatible integration, not the Ollama one; Whisper is in the same image). Local intents first so lights don't depend on the GPU; needs the roastery sleep/wake decision below (owner, 2026-09-30)
- [ ] roastery sleep vs Wake-on-LAN: design a wake-on-demand setup before it ever sleeps again. Keep it awake during SFTP, Ollama and Immich ML work (Windows puts an unattended wake back to sleep after ~2 min); a model router on grinder that wakes roastery and answers from a small CPU model meanwhile (also solves Open WebUI's machine-to-machine auth); an Immich ML fallback; a remote wake over the tailnet; a power reading first. Until then roastery stays awake (2026-09-29 decision)
- [ ] roastery rebuild after the 2026-10-07 wipe, in the order in `stacks/roastery/README.md` ("Rebuilding roastery"). First the restic repository back from Drive (`flask/RECOVERY.md` part B), with no node's key authorized until it's back (2026-10-07 entry)
- [ ] Rotate what lived on roastery before the wipe, as exposed: the Cloudflare DNS token (`traefik/secrets.env.local`, shared with every node's Traefik), `KITTEN_TOKEN`, the old tailnet device, meowGram's Postgres password (owner)
- [ ] llama-swap on roastery: `fetch-models`, `up -d`, then its README's checks; Traefik's route after it (`stacks/roastery/llama-swap/README.md`)
- [ ] Confirm the model picks (Gemma 4 12B, Qwen3.5 9B, Qwen3.5 4B on CPU) against what the LLMs are for: chat, coding, tool calls, documents (owner)
- [ ] Game mode on roastery: `game-mode\install.ps1`, then its README's checks with a real game; the launcher list in `GAME_PATHS` against what's installed (owner)

---

## 2026-10-07 — roastery wiped; llama-swap replaces Ollama, with a game mode

**roastery was wiped and Windows reinstalled** after a malware infection (owner).
Its local state went with it: every `.env.local` and `secrets.env.local`, Traefik's
binary, its rendered configs and its scheduled task, Ollama and its models,
meowGram's chat database (no backup; it had no messages on 2026-10-04), and **the
fleet's restic repository** on C:. The nodes and cellar's dumps are untouched.
Google Drive holds cellar's last `drive-sync` copy of the repository, and
`flask/RECOVERY.md` part B is the way back. Secrets that lived on roastery are
treated as exposed (Backlog). Nothing on any node was changed in this session.

**Order matters for the repository.** `drive-sync` mirrors roastery's repository
to Drive (deletions kept 30 days in `drive-crypt:deleted`). An empty
`C:\purrbrews\restic` that the nodes can log in to would be mirrored over the
Drive copy the same night. Today two things stop that: roastery's new SSH host
key doesn't match what the nodes pinned, and its new `authorized_keys` is empty.
So: repository back from Drive and checked first, nodes authorized after. Proposal,
not done: have `drive-sync.sh` refuse to sync from a repository without a
`config` file.

**Ollama → llama-swap + llama.cpp** (owner's call: Ollama was underpowered and
underfeatured). Built on branch `roastery-llama-swap`, not merged, not running.

- **Why llama-swap:** the same llama.cpp as Ollama, with every flag in view;
  an OpenAI-compatible API; Prometheus metrics; and **profiles**, named sets of
  model-ID replacements switched at runtime with one API call. Game mode is
  built on those. vLLM was ruled out: it wants the whole model in VRAM and
  reserves its cache up front, too much for 10 GB shared with games and immich-ml.
- **What runs:** `stacks/roastery/llama-swap`, image `unified-cuda-262` pinned by
  digest, published on `127.0.0.1:9292` only. Clients ask for `assistant` or
  `fast`. Profile `normal`: Gemma 4 12B Q4_K_M and Qwen3.5 9B Q6_K on the GPU.
  Profile `gaming`: both names, and the GPU models' own IDs, pinned to Qwen3.5 4B
  Q4_K_M on 4 CPU threads with `CUDA_VISIBLE_DEVICES=-1`. One model at a time,
  10 idle minutes then unloaded; no `-ngl`, so `--fit` places layers; flash
  attention and a q8_0 KV cache. Model picks are proposals (Backlog).
- **No MoE model:** 16 GB of RAM, half of it Docker's VM limit by default; the
  current 30B-class MoE files are 17 to 22 GB at Q4. Revisit at 32 GB.
- **Model files** are pinned in `config/models.lock` (revision and SHA-256) and
  fetched into a named volume by `fetch-models`, not bind-mounted from Windows
  (much slower, and llama-server maps the whole file).
- **Route:** `traefik/config/dynamic/ollama.yml.template` became
  `llama-swap.yml.template`, same middlewares, pointing at `127.0.0.1:9292`.
  **The hostname stays `ollama.${DOMAIN}`**: Authelia's rules, Pi-hole, the tunnel
  config and the tests know that name; renaming it is a fleet change of its own
  (proposal). It now speaks `/v1/...`, not `/api/tags`.

**Game mode:** `stacks/roastery/game-mode`. A watcher, run as a scheduled task at
logon with no time limit, polls every 5 s for a process under a game library
folder (`GAME_PATHS`, `GAME_IGNORE`, `GAME_EXES` in `.env.local`). On a game: profile
`gaming`, then unload every model. After 60 s without one: `normal`. It re-applies
the profile if llama-swap restarts mid-game. The flag is llama-swap's active
profile (`GET /api/profiles`), plus `state.json` and an optional webhook
(`GAME_MODE_WEBHOOK_URL`, for Home Assistant).

**Checked here, not on roastery** (no Windows or Docker in this session):

- `llama-swap -validate` (v262, built from source) accepts `config.yaml`.
- Against v262 with a stand-in `llama-server`: in `normal`, `assistant` and `fast`
  start the GPU files. After `PUT /api/profiles/active {"name":"gaming"}` and
  `POST /api/models/unload`, nothing is running, and `assistant`, `fast`,
  `gemma-4-12b` and `qwen3.5-9b` all start the 4B file with
  `CUDA_VISIBLE_DEVICES=-1`. Back in `normal`, `assistant` is Gemma again.
- `game-mode.ps1` under PowerShell 7.6 on Linux, against that llama-swap, with a
  stand-in game under `.../steamapps/common/`: start → `gaming`, models unloaded,
  webhook POSTed. llama-swap killed and restarted mid-game → logged once while
  down, `gaming` put back on the next poll. Game quit → `normal` after the grace
  period, webhook POSTed. A second copy refuses to start. `Steamworks Shared`
  ignored. `GAME_EXES` matches by name. `-Once` changes nothing.
- `fetch-models.sh` against real Hugging Face files: fresh, re-run, resumed
  `.part`, finished-but-unrenamed `.part`, 404, bad lock line, stray file.
- Every `.ps1` parses and is ASCII. `docker compose config` resolves.
  The route renders and parses. `python -m pytest tests`: 58 passed, 9 skipped.
- **Not checked:** anything on Windows: `install.ps1`, Windows PowerShell 5.1, the
  GPU, Docker Desktop's GPU passthrough with this image, real games.

**Open WebUI → llama-swap: options, none chosen.** (a) llama-swap `apiKeys`, plus a
second route that only grinder's IP may use and that skips Authelia: simple, but
it's the bypass this design has refused so far. (b) A router on grinder (the
sleep/wake backlog item) that holds the credentials and keeps Authelia's
service-account login in front. (c) Open WebUI on roastery itself, behind its own
Traefik. Until then grinder's `OLLAMA_BASE_URL` points at nothing.

**Proposals, not done:** game mode also stops immich-ml while a game runs; the
`traefik` scheduled task as a script in the repo, like game mode's; rename
`ollama.${DOMAIN}` (Authelia rules, Pi-hole, tunnel, tests, policy);
`drive-sync.sh`'s empty-repository guard (above).

**Undo:** the branch isn't merged. After a merge, revert the commits; there's no
Ollama to go back to on the new install.

**Next:** the rebuild order in roastery's README, starting with the repository;
then llama-swap, Traefik and game mode on roastery, ticking the Backlog lines with
evidence.
- [ ] Roll out branch `hardening-2026-10-08` node by node (2026-10-08 entry): per node, `git pull`, then `./compose.sh <app> up -d` for each changed app, `docker ps` until every changed container says `(healthy)`, and that node's checks from the entry. Tick per node, with what was seen
- [ ] Gatus's new checks green on sieve: `dnssec validation`, `secondary dns (mochaPot)`, `secondary dns local override (mochaPot)` (2026-10-08 entry)
- [ ] percolator: `sudo logrotate -d /etc/logrotate.d/purrbrews-traefik` after the next `./compose.sh traefik up -d`; a day later `ls /srv/data/traefik/logs` shows a rotated file and CrowdSec still reading (`docker exec crowdsec cscli metrics show acquisition`)
- [ ] percolator: `https://vault.${DOMAIN}/admin` asks for an Authelia login and lets only an admin through; the vault, its browser extension and the phone app still sign in as before
- [ ] grinder: `./compose.sh embedding-worker build --no-cache && ./compose.sh embedding-worker up -d`, then one n8n run that embeds; Dependabot's alert closes once main has the new requirements.txt

---

## 2026-10-08 — A repass of every stack: data safety, healthchecks, pins

The owner asked for every stack to be gone through, one at a time, for anything
that makes the fleet more robust: security, but mostly that it keeps working and
says so when it doesn't. Done on branch `hardening-2026-10-08` (off `main`, one
change per commit). **Nothing on any node was touched**; every change below
needs the rollout in the Backlog.

**How it was checked.** This session had a Docker engine, so instead of reading
images' docs every change was run against the real, pinned image where that was
possible: the stack brought up from its actual compose file with dummy secrets,
the healthcheck watched until Docker said `healthy`, and the failure case forced
where it could be. What couldn't be checked here is said per item. One sandbox
limit coloured several results: its kernel has no IPv6 at all, so apps that
listen on `::` by default failed to start here (that's how the IPv4 bindings
below were found).

### Data safety (the ones that matter most)

- **cellar's drive-sync could mirror an empty or different repository over the
  Drive copy.** It makes Drive match roastery; after yesterday's wipe only an
  accident of the rebuild (new host key, empty `authorized_keys`) kept an empty
  folder from replacing the offsite copy that night. It now refuses when
  roastery's restic `config` is missing or unreadable, or differs from Drive's
  (a fresh `restic init`), and the alert says why. New test, real restic and
  rclone: sync, wipe, re-init, restore from Drive. The old script fails it.
- **NetAlertX's database was copied live** (`path`), which can tear it and lose
  the whole device inventory. Now a `sqlite` dump; tested against a running
  NetAlertX: the exact `backup.sh` command, ends `COMMIT;`, restores 15 tables.
- **Actual Budget's per-budget `group-*.sqlite` files were copied live** too
  (they're the sync log; actual's `util/paths.ts`). Now dumped.
- **A glob's dump lost its path when only one file matched** (FreshRSS's one
  user came out as `users.sql.gz`). Glob lines now always name dumps by path.
  New test; fails on the old code.
- **percolator's Traefik access log was never rotated** (its README said so):
  it would have filled `/srv`. `prepare.sh` now installs a logrotate rule
  (daily or past 100 MB, 14 kept, `USR1` to reopen) and logrotate itself if
  missing. Tested with Debian's logrotate 3.22: no line lost across rotations.

### Security

- **Vaultwarden's `/admin` was reachable from the internet** (vault is published
  through the tunnel), behind only its own token. A second router puts
  `/admin` behind Authelia, admins only; two resource rules in Authelia's config.
  `authelia validate-config` passes; `check-policy` gives admins `one_factor`,
  household `deny` on `/admin` and `one_factor` on `/`; Traefik with the labels
  sends `/admin*` through ForwardAuth and the rest straight to the vault.
- **grinder's embedding-worker: sentence-transformers 3.1.1 → 5.6.0** (Dependabot's
  critical alert, CVE-2026-68770). Embeddings bit-identical to 3.1.1, so the
  vectors in postgres-vector stay valid. torch now CPU-only and pinned. Image
  built and run offline here: healthy, same vector.
- **Traefik on cellar, grinder and mochaPot** got `no-new-privileges` (as
  percolator's and sieve's already had) and a ping healthcheck.

### It works, and says so

New healthchecks, each run until healthy against the real image (failure case
in brackets where forced): Unbound (`drill-hc`; it exits 0 even on SERVFAIL, so
liveness only), cloudflared (`tunnel ready`; 503 → exit 1 with no tunnel),
Nextcloud (`status.php` JSON; maintenance mode fails it, though it answers 200),
Actual, FreshRSS, Komodo's Mongo and Core, Scrutiny, Home Assistant, Music
Assistant, embedding-worker, n8n, Meilisearch, Karakeep's Chrome, FitTrackee and
Traccar. Komodo Core and Karakeep now wait for their dependencies to be
*healthy*, not just started. Not added: Vikunja (its `healthcheck` command runs a
full init with migrations against the live SQLite every time), Gatus (no shell
or HTTP client in the image; healthchecks.io watches it), Speedtest Tracker
(couldn't be verified here). immich-ml's comment was wrong: its image has its
own healthcheck.

- **Gatus**: DNSSEC must still validate (`dnssec-failed.org` must SERVFAIL;
  otherwise validation could switch off with every check green), and mochaPot's
  Pi-hole, every client's fallback resolver, is now watched. Config loads in
  Gatus (21 endpoints).
- **IPv4 bindings**: Actual (exits 0 silently on `::` without IPv6), Komodo Core
  (can't start its server) and n8n (refuses to start). The nodes keep IPv6 in the
  kernel today, so these are the same guard as `PAPERLESS_BIND_ADDR`, not live fixes.
- **CrowdSec** mounts its acquisition file instead of the folder: on a fresh
  config directory (a rebuild) the folder mount made its first start exit 23.
- **mochaPot's kiosk** waits up to five minutes for its dashboard at boot, so a
  power cut no longer leaves Chromium on "can't be reached". Its crash recovery
  is by design (`exec cage` + getty's `Restart=always`, checked in systemd's
  unit), still to be seen on the hardware.
- **Pins**: Home Assistant 2026.10.0 and ESPHome 2026.9.1, what `stable` was today
  (same digests). A new test fails on any floating tag but Unbound's and Samba's.

### Not done, proposed

- **Memory limits** per container: worth having (one runaway app can OOM a node)
  but they need real usage numbers (`docker stats` on each node for a day) to be
  set safely; guessed limits would cause the outages they're meant to prevent.
- **Version bumps** where images are old: Meilisearch v1.10 (2024; Karakeep can
  rebuild its index), Traccar 6.2 (2024). Each is an upgrade with release notes to
  read, not a pin.
- **Paperless**: `data/index` (the search index, rebuildable with
  `document_index reindex`) could be excluded from backups.
- The `traefik` scheduled task on roastery as a script in the repo (it was made
  by hand and died with the wipe).

### Housekeeping

- Ran the suite as a non-root user too (the scripts refuse root, so 8 tests had
  never run here): 65 passed. As root with restic, rclone and sqlite3 installed:
  62 passed, 8 skipped.
- My mistake: one `git commit --amend` folded mochaPot's README note ("Home
  Assistant is pinned") into the ESPHome commit (`066f49d`). Local and unpushed,
  so nothing public changed; left as is rather than rewrite history again.
- This branch and `roastery-llama-swap` both edit this file's top, so whichever
  merges second has a small conflict here to resolve by keeping both.

**Undo:** each change is its own commit; revert the one that misbehaves.
**Next:** the Backlog's rollout lines, node by node.

## 2026-10-04 — meowGram behind roastery's Traefik, with an Authelia OIDC client; roastery's Traefik stays up

The owner built **meowGram** (a cat-lounge chat: Flutter client, Go backend,
Postgres) in its own repo, `purrMonster/meowGram`, and runs it on roastery in
Docker Desktop for now, as `meow.${DOMAIN}`. Asked for its Traefik and Authelia
config. Prepared on branch `meowgram-sso`, not merged.

**roastery's Traefik had stopped again.** Not a crash: the `traefik` scheduled task
still had Windows' 3-day limit (`ExecutionTimeLimit PT72H`; noted in the 2026-09-26
live-check item, never changed). Started at boot 2026-09-30 13:31, killed 72 hours
later, result `0x41306`. The owner unticked the limit in Task Scheduler. Checked:
`PT0S`, task running, Traefik on 80/443.

**Exposure found and fixed (owner approved).** meowGram's compose published
Postgres (5432) and the backend (8080) on every interface, and Postgres had the dev
default password that's in the meowGram repo. Both answered from cellar. Now: a
generated password (set with `ALTER USER` over psql's stdin, never shown), ports
bound to 127.0.0.1, both in a gitignored `deploy/.env`; containers recreated.
Checked: both closed from cellar, both healthy, the backend connected (0 messages,
so nothing was at stake). The backend's issuer was `http://localhost:9091`, which
inside the container is the container itself, so no token could ever have
verified; now `https://authelia.${DOMAIN}`, with its JWKS URL and `CORS_ORIGINS`
to match.

**The route:** a file route, `stacks/roastery/traefik/config/dynamic/meow.yml.template`,
to `http://127.0.0.1:8080`, like Ollama's: roastery's Traefik is native, so there
are no container labels for it to read. No ForwardAuth (the phone and desktop apps
can't follow it). DNS comes from the route as for every other; a tunnel entry to
`${ROASTERY_LAN_IP}:443` like every non-admin app (the test requires it).

**The Authelia client, and why it isn't like the others:** `public: true`, no
secret, PKCE S256; `access_token_signed_response_alg: RS256`, because the backend
verifies the access token with go-oidc and the other clients' tokens are opaque; a
`meowgram` claims policy (`preferred_username`, `name`, `email` in the access
token, or people show up as their `sub`); `audience: https://meow.${DOMAIN}`,
granted implicitly (Authelia warns an RFC 9068 token without `aud` gets rejected);
`offline_access` and `refresh_token`; OIDC CORS for origins in redirect URIs, since
the web app calls the token endpoint from the browser. Redirect URIs
`https://meow.${DOMAIN}` and `http://127.0.0.1:8088/callback`.

Checked: the rendered template (dummy values) passes Authelia 4.39.27's own
`authelia validate-config` without errors or warnings; the route renders to valid
YAML; tests pass (63, 8 skipped). Not live yet: needs the merge, the renders and
the Authelia recreate (`stacks/roastery/meowgram/README.md`).

**Open, mostly in the meowGram repo:** the backend verifies with
`SkipClientIDCheck`, so it takes any JWT Authelia signs (other apps' ID tokens
included); it should require the audience. Its build script targets a domain that
isn't the fleet's, `auth.` and client `meowgram-client`. The token rides in
`/ws?token=`. Nothing serves the web build. The chat database on roastery has no
backup; moving it to percolator later fixes the last two.

## 2026-09-29 — Clearing the noise (section 4)

Checked over SSH from roastery as `barista`, read-only, except where marked.

- **Stale backlog items**, ticked above with their evidence: the workstation, DHCP
  and DNS on Pi-hole, percolator's bring-up, ForwardAuth, Komodo's cross-host auth.
  Two stay open for the owner: whether the first node went through `bootstrap.sh`
  at the console, and a Komodo login now that registration is off.
- **Image pins** on grinder. n8n and Karakeep are pinned to the version tags whose
  registry digests match the running images, so the pin changes nothing that runs.
  Open WebUI's `main` build reports 0.11.3 but isn't the v0.11.3 release (different
  digest), and a `main` build can carry newer database migrations than the release,
  so moving to it could be a downgrade. Pinned by digest instead.
- **`local.env.example` drift:** percolator's example listed four ForwardAuth
  clients; the node itself has roastery too, since roastery's Traefik protects
  Ollama. The example now matches.
- **barista is in `docker` and `sudo` on all five nodes**, and sudo asks for a
  password. The docker group is the only reason agents can inspect and manage
  stacks without one, which is also why it's effectively root. Still the owner's
  decision (backlog).
- **`AGENTS.md`**: the working rules for every agent, from this week's lessons: one
  writer for this file, ticks only on evidence, push only on the owner's word, the
  repo is public, nodes read-only by default, other projects stay out, a handoff at
  the end of every session. Linked from `docs/MAP.md`.
- **Nodes behind `main`:** percolator, mochaPot and grinder were at `87c1379`.
- Not done here: comparing ChatGPT's collaboration proposal. It isn't in any repo;
  the owner has to paste it.

---

## 2026-09-29 — The alert paths, proven by breaking them

Section 3 of the open-items plan, run by the owner on sieve with me reading the
results. Times are IST.

**Results**

- `DISK_DEVICE`: all seven values match `lsblk` on their nodes (sieve `sda`;
  percolator `nvme0` + `sda`; cellar `nvme0` + `sda`, the Seagate; mochaPot `sda`;
  grinder `nvme0`). Every node has at most one SATA disk, so `sdX` names can't swap
  (a USB disk plugged in at boot could; plug the HDD dock in after boot). Scrutiny
  lists all seven, updated today. Its two "Failed" cards are the known attribute-188
  thresholds, not SMART failures (2026-09-26 and 2026-09-28 entries).
- Test A, stop NetAlertX: `network/netalertx` alert at 19:55 on the self-hosted
  topic, received in Chrome on roastery and on the iPhone over mobile data. That also
  proves the tunnel route for ntfy. `[STATUS] < 400` showed green on the dead service
  (status 0); the `[CONNECTED] == true` condition from 2026-09-26 is what caught it.
- Test B, stop ntfy: `network/ntfy` alert delivered by ntfy.sh. Its title arrived as
  the literal `[ALERT_TRIGGERED_OR_RESOLVED]: [ENDPOINT_NAME]`: Gatus doesn't fill
  placeholders in headers, so DOWN and back up looked the same. Fixed in this
  commit: the ntfy.sh alert goes as JSON, title in the body.
- healthchecks.io: `gatus-sieve` (period 5 min) held 3,638 pings. Gatus stopped, the
  check alerted at 21:04 with the last ping 15 minutes earlier. Its notifications
  reach the phone without anything at home. A stray check called TEST, never pinged,
  to delete (owner).

**Found on the way**

- The tunnel's ntfy route in the Cloudflare dashboard pointed at `https://sieve`.
  cloudflared sent SNI "sieve", Traefik answered with its default certificate, and
  every request from outside failed verification. Fixed in the dashboard (owner) to
  HTTP `ntfy:8080`, as the tunnel's design says. The dashboard had drifted from Git;
  the tunnel-from-Git item removes that possibility.
- Gatus's `ntfy (public)` check never used the tunnel: Pi-hole resolves the name to
  sieve's LAN address, so it stayed green while the route was broken. It now
  resolves through 1.1.1.1, like a phone on mobile data.
- The iPhone's ntfy.sh subscription had an extra character at the end of the topic,
  so it never saw a critical alert. Re-subscribed by pasting (owner). Topics and
  tokens get pasted, never typed.
- cellar's Scrutiny hub had no collector schedule, so it collected once a day while
  the other nodes collect every 6 hours. Now the same.

**This commit:** the ntfy.sh alert as JSON; `ntfy (public)` through 1.1.1.1; node
pings on for percolator, cellar, mochaPot and grinder (roastery stays out, it sleeps);
cellar's collector schedule. Tests pass (58 passed, 9 skipped).

- [x] Retest B: stop ntfy, the ntfy.sh title reads "DOWN"; start it, "back up" (owner).
  Both titles arrived filled in after the JSON change: "PurrBrews DOWN: ntfy" at 22:15,
  "PurrBrews back up: ntfy" at 22:17, and the error text no longer shows escaped quotes
- [x] Node ping test: unplug grinder's cable for 8 minutes, alert on the self-hosted topic
  (owner). `fleet/grinder` triggered 21:49, resolved 22:11
- [x] `ntfy (public)` green through the tunnel after the change. Cloudflare didn't
  challenge Gatus, so no WAF rule needed
- [x] iPhone: an alert with the phone locked and the app closed. The grinder alert
  from the self-hosted ntfy arrived that way, so iPhone delivery works as configured
- [ ] Delete the TEST check in healthchecks.io (owner)

---

## 2026-09-28 — flask, the recovery kit; where the backups' copies live

**What flask is.** The scripts and READMEs have said "copy X to flask" since the
first commits, citing a doc that has since moved out of the repo; nothing here
defined it. The owner's original plan was an SD card as a recovery device. Now
written down in [`docs/flask.md`](docs/flask.md): **two encrypted, bootable USB
sticks kept unplugged, plus the Tier 1 keys on paper.**

**Choices worth remembering:**

- **USB sticks, not an SD card:** the owner's call. USB 3.x, 64 GB, dual connector
  (A + C), two brands. Speed doesn't matter for a kit under 5 GB; 3.x sticks just
  have better parts than the 2.0 ones still on sale, and the dual connector reads
  on a phone without an adapter.
- **Two sticks and paper, because flash in a drawer fades and fails without
  warning.** The paper holds only the three Tier 1 keys and the vault's master
  password; paper outlasts any stick.
- **Never plugged into a Pi or anything online** (the owner asked). A networked box
  holding every key is the best target in the house, and ransomware reaches
  whatever is attached. Keeping the flash healthy is what the yearly check is for.
- **Bootable, through Ventoy + Debian Live** (the owner's idea). The point isn't
  the spare space: it gives a clean system to type the keys into when roastery is
  gone or not trusted, and with the offline HDD it restores with no network at all.
  Ventoy rather than a written ISO so the stick keeps an exFAT partition for the
  vault and tools; exFAT because Windows, Debian, macOS, iOS and Android all read
  it.
- **KeePassXC vault, not a password manager account:** opens on every platform and
  on the live system, with no account and no network.

**The tiers** (names and locations in `docs/flask.md`, never values): Tier 1 is
`RESTIC_PASSWORD` and the two rclone crypt secrets, without which nothing
restores; everything else is also inside the backups. Tier 2 are keys that
encrypt app data (n8n, Authelia's storage, LLDAP's seed, ...). Tier 3 are
emergency logins for when Authelia is down; Tier 4 outside accounts. Added
while writing it: the 2FA recovery codes for Google, Cloudflare, GitHub and the
Tailscale identity provider, since losing the phone must not lock those.

**Storage for the backups, decided alongside:**

- **The offline copy is cellar's old Seagate** (ST1000LM035, 1 TB), in a USB
  enclosure, synced monthly and unplugged. It's the only copy ransomware on
  roastery, an over-eager prune or a lost Google account can't touch. The
  repository is 76.6 GB (owner, 2026-09-28), so 1 TB is plenty. An old disk is
  acceptable here because it's an extra copy: roastery and Drive still hold
  everything. A new drive can replace it when prices drop: hard drives are sold
  out to data centres through 2026 and a 4 TB NAS drive is about ₹26k.
  - Checked: `lsblk` on cellar shows it unmounted, no partitions, not in fstab.
    Scrutiny's collector on cellar still reads it (`DISK_DEVICE_2`); clear that
    when it comes out.
- **roastery's repository moves off C:** (the Windows NVMe) to a second NVMe in
  the free M2B slot, the owner's pick (Crucial E100 1 TB, about ₹16k). The B450
  AORUS PRO WIFI's M2B runs at PCIe x2 and disables the ASATA ports only, which
  are unused; still ten times the network's speed. This protects against C:
  failing or a Windows reinstall, not against anything that hits all of roastery;
  that's the offline copy's job, so the offline copy comes first.

**Correction to the 2026-09-26 SMART entry:** mochaPot's SanDisk has **18,926
power-on hours**, not 665. Scrutiny's summary shows 666, but the disk's own
attribute 9 rose by 177 in the week, 7 days' worth. So its 9,924 command timeouts
are spread over about two years, not four weeks. Both disks' counts were
unchanged between 2026-09-21 and 2026-09-28 (188, 199, 5, 197, 198), which was the
week-long test that entry asked for. The SanDisk's real problem is heat: 67 °C.

- [ ] Sticks arrive: H2testw on each, then Ventoy (owner)
- [x] `make-flask.ps1`, `RECOVERY.md` (me), in `stacks/roastery/flask/`. `-PrepareOnly` on
  roastery, 2026-09-28: the four pinned keys imported by fingerprint, every signature
  and checksum good (Debian Live 13.7.0 xfce, restic 0.19.1, rclone 1.75.1, KeePassXC
  2.7.12), tools staged and `restic.exe`/`rclone.exe` run. Writing a stick isn't tested
  yet: none was plugged in. Found on the way: Git's gpg needs `/c/...` paths, not
  `C:/...`; and `_lib/purrbrews.ps1` printed a garbled `──` in PowerShell 5 (a UTF-8
  character in a BOM-less file), now ASCII, with a test that every .ps1 stays ASCII.
  The flask's restic is newer than the fleet's 0.18.0; it reads the same repository.
- [ ] Sticks tested and Ventoy on both (owner), then `.\make-flask.ps1` with both plugged in.
  2026-09-29: A done (SanDisk 3.2 Gen1, 57.3 GB): built by the owner, then `-Check` by me,
  all 142 files match its SHA256SUMS. B not seen yet.
- [x] `fill-vault.ps1` (me): Tiers 1-4 from the nodes into the vault over SSH and
  `keepassxc-cli`'s standard input, so no value is shown or written anywhere else.
  `keepassxc-cli` 2.7.12's stdin behaviour checked on roastery with a throwaway vault
  and dummy values; `-DryRun` against the real nodes finds everything in docs/flask.md
  except the Drive client and `NTFY_URL` (not set yet). It also found `CF_DNS_API_TOKEN`
  different on every node: on purpose, a token per node (owner, 2026-09-29), so the
  script keeps one entry per node for it without the warning.
  The owner's first real run then had keepassxc-cli refuse those five: their titles
  had the location in them, `(sieve/traefik)`, and keepassxc-cli reads a `/` in an
  entry path as a group. Now titled `CF_DNS_API_TOKEN (sieve)` and so on (checked on
  roastery with a throwaway vault). Also changed: a run now compares each entry with
  the node and rewrites only values that changed; notes edited by hand are left alone.
- [ ] Vault filled from the tables in `docs/flask.md` (owner; values never in a chat)
- [ ] Paper: Tier 1 keys and the master password, sealed, kept apart from both sticks (owner)
- [ ] A boot test of the stick on roastery, and a restore test from it (with the offline HDD, no network)
  - 2026-09-29, first boot test (owner): Debian Live booted from stick A. Two gaps
    my plan had missed. (1) The kit's partition wouldn't mount: the live system runs
    from it, so the kernel reports it busy. Ventoy (1.1.01+) exposes it again as
    `/dev/mapper/<partition>`; `sudo mount -o ro /dev/mapper/sdX1 /mnt/flask` worked
    (owner). (`VTOY_LINUX_REMOUNT`, in older guides, was removed in 1.1.01.) (2) The
    KeePassXC AppImage wanted libfuse2, which the owner installed from the internet;
    offline that's impossible, so the vault couldn't be opened in the one situation
    the stick is for.
  - Fix (me): Ventoy LiveInjection. `make-flask.ps1` now builds
    `ventoy/flask_injection.tar.gz` + `ventoy/ventoy.json` from
    `stacks/roastery/flask/live/`: `mount-flask` at login (mapper device, read-only,
    `/mnt/flask`, opens it), a menu entry that runs KeePassXC with
    `--appimage-extract-and-run` (no FUSE), and restic/rclone on the PATH. The ISO is
    untouched. The LiveInjection framework (1.1) isn't signed upstream, so it's pinned
    by SHA-256. RECOVERY.md and docs/flask.md updated; the hand mount goes on the paper
    too, since RECOVERY.md sits on the partition that won't mount. Tests: the live files
    are LF, `sh -n` clean, and use the mapper device, read-only and extract-and-run.
    `-PrepareOnly` on roastery built it: 7 files in `sysroot.tar.gz`, no CR bytes,
    `ventoy.json` pointing at `/debian-live-13.7.0-amd64-xfce.iso`. One thing found in
    the framework's hooks: it makes everything mode 777 and `cp -a`s the folders too, so
    `/etc` and `/usr` would come out world-writable; `mount-flask` puts them back to 755
    first thing. Not yet run on a real stick.
  - [ ] Rebuild both sticks with `.\make-flask.ps1`, then boot A **with the network
    cable out**: the kit opens by itself, "flask: KeePassXC" opens the vault, and
    `restic version` runs (owner)
  - 2026-09-30, second boot of A (owner): `/mnt/flask` mounted. KeePassXC still
    wouldn't start: run directly, the AppImage wants libfuse2; `--appimage-extract`
    in `/mnt/flask/tools/linux-amd64` failed with "Read-only file system", since it
    unpacks into the current folder, and the kit is mounted read-only. The files
    were dated 2026-09-28, so the stick most likely predates the injection build
    (not confirmed: `VERSIONS.txt` and `/usr/local/bin/flask-keepassxc` weren't
    checked). By hand it works as RECOVERY.md says: copy the AppImage to `/tmp`, run
    it with `--appimage-extract-and-run`. The rebuild above is still to do.
  - 2026-09-30, a persistent install instead of the live system? The owner asked;
    I advised against it and the owner went on with the live system. Why: `-Check`
    can only vouch for a stick that doesn't change; an installed system left in a
    drawer is a year out of date when it's needed, with no network to catch up;
    persistence keeps shell history, KeePassXC's settings and caches unencrypted on
    the stick; a running OS wears cheap flash; and flask gets booted on PCs nobody
    trusts. Whatever has to be there at every boot goes into
    `stacks/roastery/flask/live/`, injected at boot and rebuilt with the stick.
  - 2026-09-30, testing without rebooting roastery: VirtualBox with the whole stick
    as a raw disk (docs/flask.md, "Testing it"). Stick A is disk 1 on roastery. The
    first try failed harmlessly on a placeholder `N` I'd left in the commands. VM
    boot result not in yet. A VM can't test the firmware (boot menu, Secure Boot
    enrolment), so one real boot on another PC stays the final test.
- [ ] Seagate: `sudo smartctl -t long /dev/sda` on cellar, result `Completed without error` (owner); then out of cellar, into the enclosure, a full surface read on roastery
- [ ] `offline-sync.ps1` and the 35-day check (me)
- [ ] Second NVMe in roastery; the repository to `D:\purrbrews`, `setup.ps1` again, `restic check` (owner + me)

---

## 2026-09-28 — Every app over the tailnet, admin pages included

The owner wants every app reachable over Tailscale, the admin pages too; the
Cloudflare tunnel (entry below) carries only the public subset.

**How:** cellar and grinder become subnet routers for `192.168.0.0/23`, forwarding
web (443) and DNS (53) only, NATed onto the LAN. Tailscale's split DNS sends
`${DOMAIN}` lookups to the two Pi-holes. So `https://<app>.${DOMAIN}` works the same
away as at home, with the real certificate, and Authelia still decides: admin
pages still need the admin group.

**Choices worth remembering:**

- **A /23, not the house's /24.** Devices pick the most specific route, and
  Tailscale's docs say the subnet route wins over the LAN when they're equal. A
  /24 would send a laptop's traffic at home through a router node, and break SSH
  and the backdoor ports to LAN addresses while Tailscale is on. With a /23, the
  laptop's own /24 wins at home. The price: away, on a network that is itself
  192.168.0.x or .1.x, the app names don't load (SSH by tailnet name still works).
- **NAT, so no node changes.** Every node sees the requests coming from cellar's or
  grinder's LAN address, and its existing "443 from the LAN" rules apply. With
  `--netfilter-mode=off` Tailscale adds no NAT itself, so a oneshot unit
  (`purrbrews-tailscale-nat`) adds the MASQUERADE rule. UFW's `before.rules` was
  the alternative, but a nat rule there duplicates on every `ufw reload`.
- **Two routers**, so either can be down. Not sieve or mochaPot: the Pi-holes run
  host-networked there, and a router's own DNS would need extra INPUT rules.
- **The policy is the fine filter:** only the six Traefik hosts (the nodes and
  roastery) on 443, and the Pi-holes on 53. UFW on the routers forwards any
  destination on 443 (their own Traefik is a container, so after Docker's DNAT the
  destination isn't a LAN address), and only the LAN on 53.
  `autoApprovers` approves the route for tagged nodes, so no console click.
- **What stays off:** the backdoor ports, the backup SFTP, the rest of the LAN.

**Tests:** at least two routers, all real nodes; the route is one CIDR in the
settings, init's default and the policy's `autoApprovers`, and it is less specific
than `LAN_CIDR` and contains it; the web and DNS grants name exactly the `*_LAN_IP`s
and the two DNS servers from `fleet.env`; the router forwards 443 and 53 only.

**Not tested anywhere yet:** no node has run this. Checked on roastery: `bash -n`,
and the tests above.

**Rollout** (sudo and the console are the owner's):

- [ ] Paste the new `tailscale/policy.hujson` (adds `autoApprovers` and two grants)
- [ ] Admin console → DNS: custom nameservers `192.168.0.10` and `192.168.0.13`, restricted to the domain
- [ ] cellar and grinder: `git pull`, then `sudo bash init/purrbrews-init.sh --only tailscale`
- [ ] Console shows both advertising `192.168.0.0/23`, approved
- [ ] Away from home: an app and an admin page load through Authelia, a backdoor port stays closed (`tailscale/README.md` → "Is it working?")
- [ ] At home with Tailscale on: `ssh barista@192.168.0.10` still works directly

---

## 2026-09-28 — The tunnel's routes, in Git

The owner weighed Cloudflare Tunnel against Tailscale for reaching the apps from
outside, and asked for the tunnel's config file covering every app except the
admin-only ones. `stacks/sieve/cloudflared/config/config.yml.template` is that file.
It isn't wired in: the running tunnel is still the token-based one, with its routes
in the dashboard.

- **What's public:** every Traefik route except Authelia's `&admin_hosts` (traefik,
  traefik-sieve, pihole, pihole-mochapot, netalertx, gatus, komodo, scrutiny, ollama).
  That's 17 hostnames: ntfy, authelia, the percolator apps, Home Assistant and Music
  Assistant, and grinder's chat, karakeep, fittrackee and traccar.
- **LLDAP left out** although Authelia doesn't list it as admin-only: it has no
  Authelia in front, and it's the directory every other login trusts. Commented out
  in the template, with the reason.
- **n8n, ESPHome and Speedtest left out** too (owner's call, same day): n8n holds
  credentials for everything it automates, ESPHome can reflash devices, Speedtest
  has no reason to be public. Every excluded app is reachable over the tailnet
  (entry above).
- **Each route goes to its node's Traefik over HTTPS with its own name as SNI**
  (the two lessons already in the cloudflared README), so CrowdSec, Authelia and
  the real certificate apply as on the LAN. Only ntfy goes straight to its
  container, as today. Anything else gets a 404.
- **Only existing settings** (`DOMAIN`, the `*_LAN_IP`s in `fleet.env`), so sieve's
  next render doesn't stop on a new placeholder. The tunnel's UUID goes on the
  command line and its credentials stay in `/srv/data/cloudflared`, now in sieve's
  backups.
- **Tests (`Tunnel`):** the published set must equal all routes minus the admin
  hosts minus those four, so a new app forces a decision here. HTTPS and SNI per route,
  the 404 catch-all last, no new settings needed.
- **Checked:** `cloudflared tunnel ingress validate` (the pinned 2026.9.1 image, on
  roastery) says OK. `ingress rule` sends `immich.` to percolator:443, and `pihole.`
  and `n8n.` to the 404.

**Before it goes live:** two-factor in Authelia (password-only is fine on the LAN,
not on the internet); decide per app whether phone apps behind forward-auth need
bypass rules; and accept Cloudflare's 100 MB request limit and that it terminates
TLS. Tailscale stays the way in for admin pages and SSH/RDP.

---

## 2026-09-27 — Remote access over Tailscale

The owner wants SSH to the nodes and RDP to roastery from outside the house.
Decided: **Tailscale on every machine**, not one subnet router on the rack.

**Why not port forwarding:** traffic would have to cross the chained routers, and
may not get in at all if the ISP uses CGNAT; an open RDP port is brute-forced
around the clock.

**Why a client per machine rather than one subnet router** (the owner's call,
after the trade-offs): a subnet router is one box whose failure cuts off remote
access to everything; it rewrites the source address, so every node's logs and
firewall would see the router rather than the device; and access rules could only
be written against LAN IPs. A client on each machine gives each one its own name
(`ssh barista@sieve`), its own tag and its own rules, and no single point of
failure. The cost is five more installs, which init now does.

**What's in the repo:**

- `init/purrbrews-init.sh`: a `tailscale` step between `firewall` and `network`.
  Tailscale from its apt repo (same pattern as Docker's), joined as
  `tag:purrbrews-node` with `--netfilter-mode=off --accept-dns=false --reset`,
  auto-update on. UFW gets `22/tcp in on tailscale0` and `41641/udp`.
  Settings `ENABLE_TAILSCALE` (default true) and `TAILSCALE_TAGS`.
- Auth keys never go through the repo or the bootstrap server: sign in from the
  printed link, or a one-off key in `/etc/purrbrews/tailscale-authkey` (root,
  0600), deleted after use. init, `bootstrap.sh` and the bootstrap container all
  refuse a settings file with a Tailscale key in it.
- `tailscale/policy.hujson`: admins → nodes on 22; your own devices → each other
  on 3389 (`autogroup:self`); nothing from the nodes. Pasted into the admin
  console by hand, since keeping it in sync by API would need a secret in GitHub.
- `stacks/roastery/remote-access/setup.ps1`: pinned, SHA-256-checked Tailscale
  MSI (1.102.4), unattended mode, RDP with NLA, 3389 from `100.64.0.0/10` only
  (`-AllowLan` adds the LAN), Windows' own allow-all RDP rules off.

**Choices worth remembering:**

- **`--netfilter-mode=off` is the important one.** In the default mode Tailscale
  inserts its chains ahead of UFW's and accepts everything on `tailscale0`
  (Tailscale's netfilter-modes doc says so), which would have opened every port on
  every node to the tailnet regardless of UFW. With it off, UFW is again the one
  place that decides, as the README's principles want.
- **Nodes are tagged, roastery isn't.** Tagged devices belong to the tailnet and
  don't expire; roastery is a personal PC, and `autogroup:self` only matches
  devices owned by a person, which is what makes the RDP rule simple. Its key
  expiry is turned off by hand instead.
- **Not Tailscale SSH.** OpenSSH, the synced keys and barista's password-gated
  sudo stay exactly as they are; the tailnet only carries the packets.
- **`--accept-dns=false` on nodes**: Pi-hole on sieve is their resolver, and
  MagicDNS rewriting `resolv.conf` would have put a Tailscale resolver in front.
- **Web apps stay LAN-only** over the tailnet for now (443 is not opened on
  `tailscale0`); that's a separate decision.

**Not tested anywhere yet:** none of this has run on a node or on roastery, and the
Linux sandbox was unavailable, so no Docker/systemd test like earlier entries.
Checked on roastery: `bash -n` on the three changed scripts, the PowerShell parser
on `setup.ps1`, the policy parses as JSON once comments are stripped, and no file
in the repo matches the auth-key pattern (so the new guard doesn't trip on its
own docs). `python3 -m unittest` still needs a run on a Linux box.

Later the same day, on `feature/remote-access`: a `RemoteAccess` test class that
pins the decisions above. It checks that the step runs between firewall and
network; that `--netfilter-mode=off`, `--accept-dns=false` and the single
`tailscale0` SSH rule stay; that the settings' tag is owned in the policy; that
no grant starts from a tag, the node tag gets `tcp:22` only, and the policy has no
email addresses; that the three auth-key guards share one pattern, which catches a
key and not the shipped settings; that no key is anywhere in the repo; and that
roastery's installer is pinned and RDP is scoped. The class passes on roastery
(Windows Python, `PYTHONUTF8=1`), as do the two `Layout` checks that don't need
bash; the full suite still wants Linux.

**Rollout** (sudo and Windows admin are the owner's):

- [x] Admin console: tailnet created, `tailscale/policy.hujson` pasted, MagicDNS on (owner).
  Evidence: the nodes' tag was accepted, and `sieve.<tailnet>` resolves from roastery
- [x] Laptop on the tailnet (the Mac, direct connection); its key reaches the nodes
  (SSH works). The phone hasn't joined yet (backlog)
- [x] Commit and push (2026-09-27, on `main`)
- [x] Every node, once, because `main`'s history was rewritten on 2026-09-27 (domain,
  MAC and old emails scrubbed): `cd /opt/purrbrews && git fetch && git reset --hard origin/main`
- [x] `sudo bash init/purrbrews-init.sh --only tailscale` on each node (owner). All five
  online as `tag:purrbrews-node`, no key expiry (`tailscale status --json` on roastery, 2026-09-28)
- [x] `stacks\roastery\remote-access\setup.ps1`, elevated; roastery's key expiry off (owner).
  Gotcha: without `-AllowLan` it cut the owner's own LAN RDP session to 192.168.0.15 the
  moment the firewall step ran, as designed but unannounced. Kept tailnet-only: RDP from the
  Mac goes to `roastery` and still travels the LAN (direct connection)
- [x] Rebuild the bootstrap container so new nodes get the new init (`purrbrews-bootstrap`
  recreated 2026-09-28 01:44)
- [x] The checks in `tailscale/README.md` → "Is it working?" (2026-09-28). Over mobile data,
  the owner got RDP to roastery and `ssh barista@sieve` from the Mac. Over the tailnet from
  roastery: 22 answers on sieve and percolator; percolator:443 and sieve:8080 time out

---

## 2026-09-27 — roastery failed to boot after a power cut

**Symptom:** after a sudden power cut (Kernel-Power 41 at 12:10), roastery hung at the
AORUS logo / Windows spinner, then went black. Automatic Repair ran and reported it
couldn't repair the PC. The Windows installer USB hung too, which ruled out a
Windows-only problem.

**Root cause:** the old secondary HDD. It hung on every disk probe, which stalled the
Windows boot, WinRE and Windows Setup alike.

**Fix:** the HDD physically disconnected (owner). Automatic Repair still showed its
failure, left over from the earlier failed boots, but "Continue to Windows" booted
normally. Up since 16:35.

**Follow-ups** (checked 2026-09-29 on roastery by me, unless marked owner):

- [x] The backups' disk is healthy: `C:\purrbrews` is on the Samsung 1 TB NVMe
  (MZVL21T0HCLR), which Windows reports Healthy. The failed HDD is no longer attached
- [x] Nothing depends on the old HDD: pagefile at `C:\pagefile.sys`, every user shell
  folder on C:, Docker's WSL distros in their default location
- [x] Fast Startup can't run: hibernation is off (no `hiberfil.sys`). `HiberbootEnabled`
  is still 1, which is harmless while hibernation stays off
- [x] A clean boot: the current one (16:35) followed clean shutdowns at 14:15 and 14:32
  (Event 1074), with no unexpected shutdown since
- [x] Every node back after the outage: all five online in `tailscale status` from
  roastery, and each ran a successful backup on 2026-09-28 (entries above)
- [x] UPS ordered for roastery, the router and the switches (owner)
- [x] `sfc /scannow` (owner, 2026-09-29): "Windows Resource Protection did not find any
  integrity violations". DISM `/RestoreHealth` not run: it's only needed when sfc finds
  damage it can't repair
- [ ] UPS installed
- [ ] Old HDD: USB dock on a Debian node, `smartctl -a -d sat` (confirms SAT
  passthrough), `ddrescue` first if the data matters, then retire it
- [ ] roastery's NVMe in Scrutiny, via the Windows collector

---

## 2026-09-27 — Wiring the backups: plan and progress

The owner asked for the wiring too. Split by who can do each step: I can do
anything as barista over SSH and in the repo; sudo on the nodes, Windows admin
on roastery, the Google sign-in and flask are the owner's. To keep the owner's
part short, `backup.sh` gained `install` (packages, key, units) and `enable`
(doctor, a first backup, then the timers), and host keys are now pinned on
first contact (`accept-new`) instead of needing a second `keys` round.

- [x] Pull on every node, `setup-secrets` on cellar (generates RESTIC_PASSWORD and
  the crypt secrets), `ROASTERY_WOL_MAC` in cellar's `.env.local` (me)
- [x] `sudo ./backup.sh install` on all five nodes (owner): restic 0.18.0 everywhere
- [x] Collect the authorize lines; write roastery's `authorized_keys` and cellar's
  `dump-store.keys` (me). The first copy of `dump-store.keys` went through a
  PowerShell pipe and got CRLF endings; fixed with sed before anything read it.
- [x] RESTIC_PASSWORD onto the four other nodes (me, node to node through a pipe on
  roastery, never printed; checked by comparing hashes: same on all five)
- [ ] ... and to flask with the two crypt secrets (owner)
- [x] `setup.ps1` on roastery, elevated (owner): went wrong on the first run (below);
  the second run, with the fixes, put everything in `C:\purrbrews` as intended
- [x] cellar: `dump-store-setup.sh`, `restic-init.sh` (repository `3c39d63b85` on
  roastery, over rclone), after the fixes below
- [x] `sudo ./backup.sh enable` on every node, cellar first (owner); results checked (me).
  cellar: 2026-09-27 (first snapshot `e7db9b61`, Komodo's Mongo dump 11 MB); its first
  scheduled night worked (wake 01:25, backup 01:33, store 02:30, all `success`).
  2026-09-28, 03:39: sieve (`55c75a05`, 21 MiB), mochaPot (`941970d8`, 63 MiB; HA is
  still on its SQLite recorder, so the Postgres dump is empty), grinder (`32154128`,
  2 MiB). percolator started as a background service; its first full run
  took 03:40–03:56 and finished `success`. Drive sync and the 06:00 check failed, as
  expected until Drive exists. The four nodes' dumps reached cellar after the 02:30
  store run, so they're in restic from tonight's (or a hand-run `backup.sh store`).
- [ ] Drive: Google API client, `drive-setup.sh`, first `drive-sync.sh` (owner)
  - 2026-09-29: Google API client made (owner). `./setup-secrets.sh` on cellar then
    refused the client ID: "its value has a single quote or a newline". Nothing was
    stored. My first guess, a quote from the paste, was wrong: the owner got the same
    with a typed `abc`. The real bug, in `ask()` (secrets.sh) since it was written:
    it printed the newline after hidden input to stdout, which the caller captures
    as the value, so every typed answer started with a newline and was refused.
    Prompts only ever worked without a terminal (piped). The newline now goes to
    stderr. A test types into a real pseudo-terminal: it fails on the old code
    (`'[\nabc]'`) and passes now. The paste cleanup (`clean_pasted`: a \r,
    surrounding spaces, one pair of surrounding quotes) stays; it's still worth having.
  - 2026-09-29, after the fix: `./setup-secrets.sh` stored the client ID and secret
    (checked: both set, values not read). `sudo ./restic/drive-setup.sh` (owner), with
    `rclone authorize` on roastery for the Google sign-in: "drive: signed in",
    "drive-crypt: writable", "roastery: the repository is readable over SFTP";
    `/etc/purrbrews/rclone.conf` written 04:58.
  - First upload: `drive-sync.service` started by hand at 04:59:56 (owner), still
    running at 05:06; roastery was sending to cellar at about 18 MB/s, so roughly
    75 minutes for the 76.6 GB. roastery's sleep is off (`standby-timeout-ac 0`) until
    it's done; put it back after. The 06:00 freshness check will likely still see
    Drive as stale and alert: expected, not a failure.
  - [x] Upload finished: `drive-sync.service` exited 06:11:04, `Result=success`, status 0,
    and `/var/lib/purrbrews/drive-sync.ok` written at the same second (checked 12:27).
    71 minutes for the 76.6 GB. The 06:00 freshness check failed, as expected, since
    the upload was still running; tomorrow's is the first that counts.
  - [x] Restore tests on cellar, `sudo ./restic/restore-test.sh` and `--from drive`:
    both passed on the evening of 2026-09-29 (owner; output not recorded here). The
    06:00 freshness check on 2026-09-30 finished `success`, the first with Drive current
  - [x] roastery's sleep setting: decided 2026-09-29 (owner), roastery stays awake.
    AC standby stays at Never. The 01:25 Wake-on-LAN timer stays as a harmless
    fallback; it does nothing while roastery is already on
  - [ ] Drive client ID/secret into the vault (`fill-vault.ps1` again) and
    `rclone.conf` attached; the vault copied to stick B, `-Check`
- [x] Restore test from roastery and from Drive; next morning's freshness check
  (both above)
  - 2026-09-30, the first full night with everything on, checked 10:04 over SSH (me):
    every unit `Result=success`, status 0. Wake 01:25; nightly backups on cellar
    01:30, sieve 01:31, mochaPot 01:32, percolator 01:32, grinder 01:35 (3–25 s each,
    incremental); store 02:30; drive-sync 03:30–03:31; freshness check 06:00.
  - The one failure: `restic-prune.service` on Sunday 2026-09-27 at 03:30:20, exit 1,
    "run with sudo: the repository is reached with root's backup key". That was the
    catch-up run when the timers were switched on. The installed unit matches the
    repo (no `User=`, so a timer run is root); barista could read the line in the
    journal, which points to a run as barista rather than by systemd. Not confirmed.
    Rerun 2026-09-30 by the owner (`sudo systemctl start restic-prune.service`):
    "prune OK" at 10:33:31. Nothing removed: three nights of snapshots, each still
    a keeper. Next prune Sunday 2026-10-04 03:00; first monthly verify 2026-10-01 04:30

**What went wrong on the first pass, and the fixes:**

1. **`setup.ps1` made the repo itself the chroot and locked its owner out.** Its
   `-Root` parameter was `$Root`; dot-sourcing `_lib/purrbrews.ps1` sets
   `$script:Root` (the repo path) in the same scope, which silently won. So the
   script replaced the ACL on `C:\Users\jyotirmoyc\Desktop\Projects\purrbrews-containers`
   (SYSTEM, Administrators, restic; inheritance off), created the repository
   folder inside it, and pointed `ChrootDirectory` at it. A non-elevated session
   (git, the editor, Desktop Commander) got "Access is denied". Nothing was
   deleted. Repair, elevated: remove the stray `restic\` folder, `icacls <repo>
   /reset /T`, stop sshd until the fixed script has run.
   Fix: the parameter is `$BackupRoot`, and the script refuses any folder that's
   a drive root, under `C:\Users`, or has a `.git`, because it replaces that
   folder's permissions outright.
2. **restic's SFTP backend can't write to Windows' OpenSSH.** Every file restic
   writes, it chmods; Windows' sftp-server answers `SSH_FX_BAD_MESSAGE`, and
   `restic init` retried its first key forever. Fix: restic reaches roastery
   through `rclone serve restic --stdio` with rclone's SFTP backend
   (`set_modtime=false`, `shell_type=none`), defined in the environment by
   `restic-env.sh`: same account, key, chroot and path, no chmod, no SETSTAT.
   rclone is now installed on every node. Tested in the sandbox against a real
   sshd (init, backup, snapshot readable by plain restic); not yet against
   Windows.
   rclone checks host keys strictly and may negotiate a type other than the one
   pinned, which it reports as a mismatch, so every key type roastery offers is
   pinned now (a changed key is still refused). cellar's pinned ed25519 key
   (`SHA256:T+Jb1G7…`) matches what `setup.ps1` printed.
3. **cellar's sshd only allows barista** (`AllowUsers barista`, init's drop-in),
   so the nodes couldn't have pushed dumps. `dump-store-setup.sh` now writes its
   own drop-in, `20-purrbrews-dumps.conf` (`AllowUsers dumps`, key-only), checks
   it with `sshd -t` and reloads; it only warned before.
4. **The host-key pinning wrote garbage into cellar's known_hosts.** Debian 13's
   `ssh-keyscan` prints its `# host:22 SSH-2.0-…` banners on stdout; the new
   pinning took them for keys, and rclone refuses a known_hosts file with even one
   bad line ("illegal base64 data"), so `restic-init` failed again, this time
   before reaching roastery. Worse, `ssh-keygen -F` stopped matching in the broken
   file, so each run re-added everything. Fix: only lines that look like keys are
   taken, and `tidy_known_hosts` cleans the file (non-key lines, duplicates) on
   the next run, so cellar repairs itself. The pinned keys themselves were right.
5. **cellar still had the HDD-era `restic-backup.timer` enabled** (last ran 02:00,
   its script is gone). `backup.sh install` now disables and removes
   `restic-backup` and `mirror-to-roastery` units wherever it finds them.

**Coordination with the remote-access session** (the owner relayed its checklist):

- `docs/runbook-catch-up` on GitHub was built on the pre-rewrite history and
  carried the old addresses in its commits; deleted. Its only content worth
  keeping, four runbook entries (09-17 to 09-25), is re-added further down from its
  text, not its commits; its README tweak was already superseded on `main`.
- History operations are one session's job, and not this one's from here on:
  no force-pushes to `main` without the owner's go-ahead; the `backup/*`
  branches, `stash@{0}` and `feature/remote-access` stay untouched.
- Before every push: `git log origin/main..HEAD --format='%ae %ce'` shows only
  `jyotirmoy.github@jyotirmoy.cc`, and a `git grep` for the real domain over the
  new commits finds nothing (the pattern itself stays out of the repo).
- The repo folder's permissions are all inherited again (no `restic` entry;
  checked with `icacls`), and `setup.ps1` now refuses any backup root other than
  `<drive>:\purrbrews`.
- The nodes were reset to the rewritten history once (`git fetch && git reset
  --hard origin/main`) and have pulled normally since.

---

## 2026-09-27 — Backup scripts written (not tied together yet)

Every script the design above needs, across all nodes. Nothing is installed,
enabled or run on a node yet; that's the next session ("tying together", in the
order in `stacks/cellar/restic/README.md`).

**What exists now:**

- **Per node, one script and a config file per app.** `_lib/backup.sh` (every Linux
  node's `./backup.sh`, the same wrapper as the other four) with `plan`, `doctor`,
  `keys`, `dump`, `push`, `files`, `store`, `nightly` and `restic`. What to back up
  is each app's `backup` file: `pg`, `mongo`, `sqlite` (dumps), `path`, `exclude`.
  25 of them, covering every app with state worth keeping; the ones left out are on
  purpose (Traefik certificates, Scrutiny history, Meilisearch, Redis/Valkey,
  mochaPot's secondary Pi-hole, Speedtest results, the Gatus history).
- Every node also always backs up its own `.env`, `.env.local`, every
  `secrets.env.local` and `/etc/purrbrews`: what rebuilding a node needs.
- Dumps are read back before they replace the last good one (`pg_restore --list`,
  a trailing `COMMIT;`, `gzip -t`); SQLite is dumped as the file's owner, read-only,
  so a root `sqlite3` can't leave a root-owned `-shm` that locks the app out; the
  Mongo password never appears in a process list.
- `_lib/restic-env.sh`: the shared pieces (repository, keys, pinned host keys,
  ntfy, locking, wake-on-LAN), so the node side and cellar's side can't drift.
- `_lib/systemd/purrbrews-backup@.{service,timer}`: one unit for every node, 01:30.
- **cellar/restic**, rewritten around roastery: `restic-init`, `dump-store-setup`
  (the `dumps` account; each node's key locked by `rrsync -wo` to its own folder),
  `wake-roastery`, `restic-prune`, `drive-setup`, `drive-sync`, `check-freshness`,
  `verify`, `restore-test`, and their timers. The old `restic-backup.sh` and
  `mirror-to-roastery.sh` are gone, with the HDD repository they served.
- **roastery**: `backup-target/setup.ps1` (OpenSSH, the `restic` account, the chroot,
  `AllowUsers restic`, the firewall rule from `fleet.env`, wake-on-LAN, and a
  3-hour unattended-wake window).
- `fleet.env` now has `ROASTERY_LAN_IP`, `BACKUP_REPOSITORY`, `DUMP_DIR` and
  `DUMP_STORE_HOST`; grinder's `ROASTERY_LAN_IP` moved there from its example.
- Tests: every node's `plan` parses, bad lines are refused, excludes stay inside
  their app, and a dump + files + store run into a local repository (restored and
  checked). 44 pass.

**Tested for real in a sandbox** (not on the fleet): the SQLite dumps (a live WAL
database, owner-only), `files` with the excludes, `store`, stale-dump cleanup, a
failed dump keeping the last good one, `keys`, `doctor`, and the push to a real
sshd + rrsync (`-wo` refuses a read and a shell). Not tested anywhere yet: SFTP
into Windows OpenSSH with a chroot (the one part I'm least sure of; if the chroot
fights back, drop `ChrootDirectory` and use `sftp:restic@…:/C:/purrbrews/restic`
in `fleet.env`), `setup.ps1` itself, wake-on-LAN, and rclone against Drive.

**Changed from before, and why:**

- **rclone's config is no longer a rendered template.** rclone writes the refreshed
  OAuth token back into its config; render-configs would have overwritten it on the
  next run. It's `/etc/purrbrews/rclone.conf` now, made once by `drive-setup.sh`.
- **The Google OAuth app has to be published, not left in Testing** (the old README
  said Testing): refresh tokens of a Testing app expire after 7 days.
- **The crypt passwords are generated secrets** (`RCLONE_CRYPT_PASSWORD`/`_SALT` in
  `restic/secrets.conf`), so they go to flask like everything else, and the crypt
  remote is `drive:purrbrews-restic` (nothing was ever uploaded to the old one).
- **Windows' unattended-sleep timeout** (2 minutes after a wake with nobody there)
  would end every backup before it started. `setup.ps1` sets it to 3 hours, and
  every cellar job wakes roastery itself rather than trusting the 01:25 wake.
- **Deleted snapshots are recoverable for 30 days** on Drive (`--backup-dir`), since
  SFTP has no append-only mode.
- roastery has no DHCP reservation, and `BACKUP_REPOSITORY` now depends on
  192.168.0.15; that backlog item matters more now.

---

## 2026-09-27 — Backup design, decided

The owner left the three open questions from the entry below to me ("for my
hardware and design, take a decision"). What I measured first:

- **Data is small.** percolator uses 89 GB of `/srv` (Immich, Nextcloud, Paperless
  files and databases); every other node's `/srv/data` is under 1 GB, grinder's
  Open WebUI the largest at 890 MB. Call it ~100 GB to protect today.
- **roastery's disks:** C: is a Samsung 1 TB NVMe (PM9A1, healthy, 667 GB free).
  D: is another **ST1000LM035**, the same old 2.5" Seagate model as cellar's
  restic disk, 335 GB free.
- **cellar's disks:** the old Seagate (`/srv/backup`) and a 256 GB NVMe for the
  system, 208 GB free.
- roastery sleeps in S3 and wakes on the USB Realtek NIC (the onboard I211 isn't
  connected), which is what `mirror-to-roastery.sh` already expects.

**Decisions:**

1. **The repository lives on roastery's C: (NVMe)**, in `C:\purrbrews\restic`, not
   on D:. D: is the same old laptop disk we're moving away from. C: being the
   system disk is the usual objection (a reinstall could take it); the Google Drive
   copy covers that, and at ~100 GB it has years of room.
2. **Nodes reach it over SFTP**: Windows' OpenSSH Server on roastery, a dedicated
   non-admin local account `restic`, key-only, its home the repository folder.
   Windows Firewall allows 22 from the five node IPs only. Why not the others:
   OpenSSH is a Windows service that runs before anyone signs in (Docker Desktop and
   rest-server don't), and restic speaks SFTP natively. SMB is the easiest to
   break and the usual ransomware target.
   - The cost: rest-server's append-only mode is gone, so a node with the key
     could delete snapshots. Covered by the Drive copy keeping deleted files
     (`rclone sync --backup-dir`, 30 days), below.
3. **Dumps through cellar, files straight to roastery** (option B):
   - Every node dumps its own databases at 01:30 (pg_dump / mongodump) and pushes
     them to cellar's `/srv/dumps/<node>`, **on cellar's NVMe**, not the old HDD.
   - Every node backs up its own file data straight to the roastery repository at
     02:15 (`--host <node>`). Only percolator has much; the rest is config-sized.
   - cellar backs up `/srv/dumps` and its own data the same way.
   - Built config-driven like the rest of `_lib`: an app lists what to dump and
     which paths to back up in a small per-app file; no per-node scripts.
4. **cellar orchestrates**, since it's the one that's always on: wakes roastery at
   02:00 (WoL), syncs the repository to Google Drive at 04:00 (rclone reads it over
   SFTP, through the existing `drive-crypt` remote), prunes on Sundays (one host
   prunes, so there's no lock fight), and at 06:00 checks every host has a snapshot
   under 26 hours old. Anything missing or failed goes to ntfy.
5. **cellar's old Seagate** stops being used for backups at all. It can stay as
   scratch until it's replaced.

**Order of work:**

1. roastery: OpenSSH Server, the `restic` account, the firewall rule, `C:\purrbrews\restic`
   (owner-approved system change; I prepare the exact commands).
2. `restic init` on the SFTP repository; `RESTIC_PASSWORD` to flask the same day.
3. Dump job in `_lib`, dump files for percolator (Nextcloud, Immich, Paperless),
   cellar (Komodo's Mongo), grinder (FitTrackee, postgres-vector), mochaPot (HA
   recorder); push to cellar.
4. File backup job in `_lib`, per-app path lists, timers on each node.
5. cellar: WoL timer, Drive sync repointed at the SFTP repo, freshness check.
6. **Restore test** from the Drive copy: one database and one photo folder. Not done
   until this passes.

Also noticed: roastery's own D: (documents, projects, `insta360`) sits on that same
old Seagate model with no backup. Adding a Windows restic job for it later is cheap.

---

## 2026-09-26 — Backups move to roastery; cellar becomes the dump store

The restic disk on cellar is 5–8 years old and holds the only copy of the
backups (Scrutiny finding in the entry below).

**Decided (owner):** cellar stops being the backup target and becomes the dump
store, where each node's database dumps and exports land. Backups (restic) move to
roastery. Everything gets a second copy on Google Drive. Work starts 2026-09-27.

To settle while doing it:

- How the nodes reach a restic repository on roastery (rest-server in Docker
  Desktop, SFTP, or a share), and the Windows Firewall rule scoped to the fleet.
- roastery is a workstation: backups only run while it's on and signed in, the same
  gap Ollama has. Decide the schedule around that, and alert (ntfy) on a missed run.
- The Google Drive copy: copying the restic repository covers everything restic
  backs up and is already encrypted, so a plain rclone copy is safe. Anything
  copied outside restic (raw dumps) needs encrypting first (rclone crypt).
- cellar's old disk is fine as a dump store, since the dumps are no longer the
  last copy; the replacement item in the backlog can wait until this is done.

---

## 2026-09-26 — Live check after the cleanup rollout: findings and plan

Every node has pulled the cleanup. From Chrome on roastery I opened every Traefik
hostname in the repo and the direct ports: 25 of 30 hostnames answer as they should.
barista was added to the `docker` group on every node today so containers can be
inspected without sudo. That makes barista root-equivalent without a password, which
the README's least-privilege principle rules out; it stays a conscious exception
until decided otherwise (backlog).

**Findings, and what I'll do about each** (ticked as each is fixed and verified):

- [x] **FitTrackee is down.** `fittrackee.${DOMAIN}` is a 502 and `:5001` refuses.
  Plan: read its logs on grinder, fix, recreate.
  - Cause: FitTrackee 1.x needs PostGIS and the database was plain `postgres:16`.
    The migration dies at `ADD COLUMN geom geometry(...)` ("type geometry does not
    exist"), rolls back, and the container restarts every ~10 s. It never got past
    that, so the database has no tables and nothing is lost.
  - Fix: `postgis/postgis:16-3.5` (same major, same data directory), then
    `CREATE EXTENSION postgis` in the FitTrackee database, since the image only does
    that on a fresh directory. The old directory was initialised on trixie (16.15) and the
    PostGIS image is bullseye (16.9, glibc 2.31): same on-disk format, but the
    (empty) databases need `ALTER DATABASE … REFRESH COLLATION VERSION`. An older
    base than I'd like; it's the tag upstream maintains for 16.
  - Done on grinder: migrations now run to the end. The next start then stopped at
    gunicorn's log file (`/usr/src/app/logs/gunicorn.log`, a directory the image
    doesn't have); `GUNICORN_LOG=-` sends it to stderr instead. `uploads` was
    created root-owned while the app runs as 1000, so `data-dirs` says 1000:1000
    now. data-dirs never touches an existing directory, so grinder needs, once:
    `sudo chown -R 1000:1000 /srv/data/fittrackee` (owner's step, needs sudo).
  - Done: chowned; the container can write to `uploads`, and the hostname sends
    you to Authelia.
- [x] **Home Assistant through Traefik answers 400 to everything**; `:8123` works.
  HA is rejecting Traefik as an untrusted proxy. Plan: compare `mochapot_net`'s real
  subnet with `http.trusted_proxies` (node-local `configuration.yaml`, not the repo).
  - Cause: `/srv/data/homeassistant/configuration.yaml` has no `http:` block at
    all; HA logs "untrusted proxy 172.30.13.2" (Traefik on `mochapot_net`,
    172.30.13.0/24). The README's block was never pasted in. The file is
    root-owned, so this is the owner's step: add the `http:` block from
    `stacks/mochaPot/homeassistant/README.md` with `sudo`, then
    `./compose.sh homeassistant restart`.
  - Done: `http:` block added. `homeassistant.${DOMAIN}` answers 200 and HA logs no
    more untrusted-proxy errors.
- [x] **Komodo through Traefik never gets past its loading spinner**; `:9120` shows
  the login. Plan: Traefik and Core logs on cellar, websocket path.
  - Cause: not cellar at all. The UI sends its own token in `Authorization`;
    Traefik passes that to Authelia's forward-auth, whose default also treats the
    header as a login attempt. A bare token isn't valid Basic auth, so Authelia
    answered 401 with `WWW-Authenticate: Basic`, and Chrome held `GET /user` and
    `POST /read/GetCoreInfo` on a password prompt it never showed. Direct to 9120
    and without the header, both answer in milliseconds.
  - Fix: Authelia's `forward-auth` endpoint goes by the session cookie only; a
    second endpoint, `forward-auth-basic`, keeps Basic auth for the Ollama
    service accounts, and roastery's ollama route points at it.
  - Done: rendered and Authelia recreated on percolator (config validated with the
    same image first). `komodo.${DOMAIN}` now shows Komodo's login.
- [x] **ollama.${DOMAIN} refuses**: roastery's native Traefik isn't running (Ollama
  itself answers on localhost). Plan: confirm, and decide whether it should start
  on its own.
  - Cause: it does start on its own: the `traefik` scheduled task runs `start.ps1`
    at boot. It exits 1 every time because Windows Application Control blocks
    `traefik.exe` ("An Application Control policy has blocked this file"). Config,
    renders and the token are all fine. Owner's decision: allow the binary (or turn
    Smart App Control off), or run this Traefik somewhere else.
  - The same task has Windows' default 72-hour execution limit, so even once it
    starts it would be killed after three days. Set it to no limit when fixing the
    above (task settings, "Stop the task if it runs longer than").
  - 2026-10-04: that limit is what stopped it again. Started at boot 2026-09-30
    13:31, killed 72 hours later (last result `0x41306`, terminated, not a crash).
    Owner set the task to no limit; checked: `ExecutionTimeLimit` `PT0S`, the task
    running (`0x41301`) and Traefik listening on 80/443 (2026-10-04 entry).
- [x] **Gatus: "ntfy (public)" and "traefik certificate + sso" time out** from sieve,
  while both answer from the LAN. Plan: check what the gatus container resolves and
  reaches for those names.
  - Cause: both names resolve to sieve's own address, 192.168.0.10. From a
    container, a published port on the host's own IP is answered by docker-proxy
    on the host, i.e. the INPUT chain, and UFW has no INPUT rule for 443 from
    `sieve_edge` (the `route` rules only cover FORWARD). Checked from the ntfy
    container: `https://192.168.0.10/` times out, Traefik's container IP answers.
  - Fix: `allow tcp 443 NETWORK` in `sieve/traefik/firewall`. Takes effect with the
    firewall run below (`sudo ./firewall.sh` on sieve).
  - Done: after the firewall run both checks pass (16–25 ms).
- [ ] **Paperless shows "Error loading settings"** on its dashboard. Plan: logs.
  - Cause: `/api/ui_settings/` and `/api/saved_views/` answer 403. The account
    Authelia created on first sign-in has no permissions at all; step 2 of the
    README's first run (make it a superuser) was never done. Owner's step: sign in
    as `admin` and tick *Superuser* on that user, as the README says.
  - Still open after the owner's pass: `admin` has never signed in and the SSO user
    is still not a superuser, so the API still answers 403.
- [ ] **Scrutiny flags attribute 188 (command timeout)** on cellar's 1 TB Seagate
  (the restic disk) and mochaPot's 128 GB SanDisk. SMART itself passes. Plan: note
  the counts, check cables, watch the trend before trusting backups to that disk.
  - Counts on 2026-09-26. Seagate ST1000LM035 (cellar): 188 raw 4295032858, which
    is Seagate's packed form: 0x1_0001_001A, three counters of 1, 1 and 26, so a
    few dozen timeouts at most, at 18 905 power-on hours; reallocated 0, UDMA
    CRC (199) 1. SanDisk 128 GB (mochaPot): 188 = 9924 at 665 hours; reallocated
    0, CRC 0.
  - Read: the Seagate looks like an old, small count rather than a failing disk;
    the one CRC error points at the cable or the USB bridge. The SanDisk's number
    is high for its age. Next: re-seat or swap the cables, and compare these
    numbers in a week. If either keeps climbing, it doesn't hold backups.
  - Both disks are 5–8 years old (owner, 2026-09-26). That changes the plan more
    than the counts do: the Seagate's 18 905 hours is only ~2 years powered on,
    but it's an old 2.5" laptop disk and it holds the only copy of the backups.
    Plan: get a second copy off it first (the Google Drive sync in the backlog),
    run a long SMART self-test on both (`sudo smartctl -t long`, owner's step), and
    budget a replacement for the restic disk rather than waiting for it to fail.
- [x] **The firewall's `route` rules don't restrict LAN clients.** Correction to the
  entry below: I wrote that grinder's old rules "never matched". The port numbers
  were wrong (they match the container port), but it didn't matter, because every
  published port answers from the LAN anyway, including Authelia's 9091, which is
  meant for `FORWARD_AUTH_CLIENTS` only. ufw-docker installed without
  `--docker-subnets` puts `RETURN -s 192.168.0.0/16` (and 10/8, 172.16/12) ahead of
  the rules, so anything from a private address is let through. Only host-networked
  ports (sieve's Pi-hole UI) are really filtered. Plan: init installs ufw-docker with
  `--docker-subnets` (only Docker's own subnets bypass), re-run on each node with
  sudo, then check a port that should be closed from roastery is closed, and one that
  should be open is open. Before that, confirm roastery's IP is in
  `FORWARD_AUTH_CLIENTS` if its Traefik is to keep using 9091.
  - Repo side done: init and `_lib/firewall.sh` now run
    `ufw-docker install --docker-subnets` (firewall.sh every time, since the list
    of Docker networks is read when it runs) and restart ufw when that changed
    anything. Still to do, on each node, with sudo: `sudo ./firewall.sh`, then the
    two checks above.
  - Owner ran `sudo ./firewall.sh` on every node. From roastery (192.168.0.15): Authelia's
    9091 and sieve's Pi-hole UI are now closed; the ports the `firewall` files open to
    the LAN (FitTrackee 5001, Komodo 9120, HA 8123, Traefik 443, DNS) are open.
  - It broke SSO on cellar, mochaPot and grinder: only sieve could still reach 9091,
    so their protected pages timed out. percolator's `.env.local` still had
    `FORWARD_AUTH_CLIENTS=192.168.0.10`, from before the other nodes were added to
    `local.env.example`; setup never changes a value that's already set, so the
    example's update never reached the node. The route rules only mattered now that
    ufw-docker stopped letting the whole LAN through. Set it to the example's four
    addresses (backup: `.env.local.bak-20260926`). Needs one more
    `sudo ./firewall.sh` on percolator. roastery is not in the list; add
    192.168.0.15 too if its Traefik comes back.
  - Done (2026-09-27): owner re-ran it on percolator. 9091 answers from sieve,
    cellar, mochaPot and grinder and is closed from roastery; every protected
    hostname redirects to Authelia again.

---

## 2026-09-26 — One toolkit for every node

The nodes had drifted. percolator's `compose.sh` checked stale renders and made data
directories; cellar's validated the resolved config; grinder's and mochaPot's did
neither; roastery's didn't use sudo at all. Every node had its own copy of
`generate-secrets.sh` with slightly different quoting, and adding an app meant
editing three scripts on that node and remembering which one had which bug fixed.

**Decided: one set of scripts in `stacks/_lib`, and config instead of code.**

- Every node's `compose.sh`, `setup-secrets.sh`, `render-configs.sh` and `firewall.sh`
  is the same three-line wrapper. Everything node-specific is in `node.conf`: `APPS`
  in bring-up order, `NETWORK` (and the key holding its fixed subnet), `RESOLVER`
  (primary/secondary Pi-hole).
- Per app, optional: `secrets.conf` (what to generate or ask for), `firewall` (UFW
  rules), `data-dirs`, `prepare.sh`, templates. Adding an app is a folder plus one
  word in `APPS`.
- Every node now gets percolator's pre-`up` checks: renders current, data directories
  made with the right owner, no `REPLACE_ME` in the resolved config.
- `stacks/fleet.env` holds what every node shares (node IPs, LAN, gateway, TZ, the
  two resolvers). The per-node copies of `CELLAR_LAN_IP`, `PERCOLATOR_LAN_IP`,
  `SIEVE_IP`, `AUTHELIA_URL` are gone from the examples; existing `.env.local` lines
  are harmless (later files win and the values are the same). A test keeps
  `fleet.env` in step with `NODE_IPS`.
- Compose files use `${NODE_IP}`, `${NODE}`, `${DATA_DIR}` and `${MEDIA_DIR}`, so
  the Komodo Periphery and Scrutiny collector files are identical on every Linux node.
- Renamed keys (`ACME_EMAIL` → `TRAEFIK_ACME_EMAIL`, every `*_DISK_DEVICE*` →
  `DISK_DEVICE`/`DISK_DEVICE_2`) are listed in `_lib/renamed-keys`; setup and
  `compose.sh` copy the old value across, so a pull never strands a node.
- The DHCP static leases moved from sieve's setup script into `dns-records.py`
  (primary role only), so both Pi-holes are driven the same way.
- roastery gets PowerShell twins (`_lib/purrbrews.ps1`) of setup, render and compose,
  checked against the bash renderer by a test.
- One root `.gitignore` instead of five that disagreed; every rendered file is
  listed, and a test fails if a template's output isn't.

**Fixed on the way:**

- grinder's backdoor rules named the published ports (5001, 3030, 8081, 8765).
  ufw-docker's `route` rules match after DNAT, on the container port, so those
  never matched. They now say 5000, 3000, 8080, 80.
- Komodo's `KOMODO_DISABLE_USER_REGISTRATION` was `"false"` under a comment
  explaining why it should be off. Now `"true"`.
- Speedtest Tracker's generated `APP_KEY` was hex behind `base64:`, which decodes to
  the wrong length. New installs get real base64; an existing key is left alone.
- An unquoted `FORWARD_AUTH_CLIENTS` (it has spaces) broke `source` in the renderer.
  Setup now quotes such values in place.
- init's closing hint said `sudo ./setup-secrets.sh`, which is exactly what not to do.
- A comment in mochaPot's Home Assistant file had the real domain in it, and one in
  cellar's mirror script had roastery's real MAC. Both gone from the files (they are
  still in the old history).

**Also:** history on `main` was rewritten (the merge linearised, fixups squashed,
terse messages reworded). Nodes need a one-time `git fetch && git reset --hard
origin/main`; their daily `--ff-only` pull fails until then. `runbook_1.md`, a plan
document that now lives elsewhere, and roastery's tracked Komodo keys were
removed.
Every README now describes what's running rather than what was planned, and
comments explain why rather than retelling history; the history is here.

---

## 2026-09-25 — Every stack running

*Recovered on 2026-09-27 from the `docs/runbook-catch-up` branch, which was built
on the pre-cleanup history and never merged; the branch itself was deleted
because its old commits carried personal details. These four entries (09-17 to
09-25) are kept as they were written. Some specifics have moved on since: the
toolkit was unified on 2026-09-26, `stacks/roastery/README.md` exists again, and
the backups are the 2026-09-27 design.*

Status checkpoint, reported by the owner: every stack on sieve, percolator,
cellar, mochaPot, grinder and roastery is up and working. The backlog above is
ticked to match. What stays open is not "does it run" but "is it safe to lose":
database dumps, restic sources, a restore test, alert-path break tests and Gatus
coverage.

Nothing between 2026-09-16 and this entry was written down at the time. The
three entries below reconstruct it from the commits and the comments they left
in the compose files, which carry the full detail.

## 2026-09-22 — roastery's Traefik for Ollama; service-account groups in Authelia

**roastery runs a native Windows Traefik** (`stacks/roastery/traefik/`, started by
`start.ps1`), not a container. It fronts Ollama on `localhost:11434` as
`ollama.${DOMAIN}`, behind ForwardAuth to Authelia on percolator like every other
node. roastery's IP was added to `FORWARD_AUTH_CLIENTS`, and `ollama` to the
admin-host list with its deny fallback. The binary is downloaded and
checksum-verified by hand; `data/acme.json` and the rendered files are never
committed.

**Machine clients get their own LLDAP groups, not admin accounts.**

- `ollama_api_group`: `one_factor` on `ollama.${DOMAIN}` only, so API clients
  can call Ollama with a password. People still need an admin login.
- `nextcloud_bot_accounts`: `one_factor` on `nextcloud.${DOMAIN}` and
  Nextcloud's OIDC client (its own `nextcloud` authorization policy), and
  `deny` on every other host. These rules sit before the admin/household
  rules, so a bot that also lands in a human group still can't wander.

The old `stacks/roastery/README.md` was removed in the same merge; the Traefik
README is the only roastery doc now.

## 2026-09-18 — Fleet audit: DNS consistency, DHCP on sieve, Diun removed

A read-only audit of the running fleet against the repo, recorded in full in
[docs/network-audit.md](docs/network-audit.md). The decisions:

- **Changes reach nodes through Git only.** Commit, push, pull on the node. Files
  copied straight to a server during the audit were superseded, not activated.
- **One shared render/DNS library** in `stacks/_lib/` (`render-template.py`,
  `render-configs.sh`, `dns-records.py`, `refresh-dns.sh`) replaced each node's
  copy-pasted `render-configs.sh` logic. Rendering is atomic: a failed template
  leaves the old file in place. Offline tests in `tests/` cover it
  (`python3 -m unittest discover -s tests -v`).
- **Both Pi-holes serve the same records.** mochaPot's secondary now gets local
  records and allows LAN DNS on 53. Before this, it answered only on its own host.
- **Hosts use LAN DNS only.** `init/use-lan-dns.py` moves an existing node's
  NetworkManager profile to .10/.13 and verifies it. A public fallback resolver
  can't resolve private names, so it only hid failures. The router's IPv6 RA is
  off, but NetworkManager keeps IPv6 DNS it already learned, so each host still
  needs the migration.
- **DHCP is sieve's, permanently.** Routers had DHCP off and Pi-hole's was
  inactive, so nothing on the LAN was handing out leases. sieve's Compose now
  pins `FTLCONF_dhcp_active: "true"` and mochaPot's `"false"`, overriding
  whatever Pi-hole persisted. `stacks/sieve/enable-dhcp.sh` is the handover.
- **cellar refuses unresolved placeholders.** Komodo was serving Traefik's
  default certificate because a container created before `DOMAIN` was set kept
  `komodo.REPLACE_ME…` in its labels. `_lib/check-compose-config.py` now checks
  the resolved Compose config before `up`. Labels only change on recreate, never
  on restart.
- **Windows App (AVD) allowlist lives in `pihole/allow-wvd.py`**, driven through
  Pi-hole's local API, so the exception survives a gravity rebuild.
- **Diun removed** from cellar. It never had a notification target, so it
  watched and told no one. Nothing replaces it yet; image tags stay pinned and
  are bumped by hand.

## 2026-09-17 — First real bring-up: what broke and why

The stacks met real hardware. Every fix below left a dated comment at the spot in
the compose file; this is the index.

**Silent failures, the worst kind:**

- **Traefik dropped Authelia's router without an error.** Authelia is on two
  networks (`proxy` and its Redis network), and Traefik can't guess which IP to
  use. The symptom was a plain 404 on `authelia.${DOMAIN}`. Fixed with
  `traefik.docker.network=proxy`. Any container on two networks needs this label.
- **Quoted Traefik labels never got Pi-hole records.** sieve's DNS generator
  matched `- traefik.…` but not `- "traefik.…"`, so nine newer apps quietly had
  no DNS. mochaPot's labels were unquoted first, then the generator was fixed to
  accept both styles. It now lives in `_lib/dns-records.py` and also reads
  Traefik file-provider routes.
- **Containers with `network_mode: host` keep the DNS they were born with.**
  Docker snapshots `/etc/resolv.conf` at creation. Home Assistant was created
  while mochaPot still used bootstrap DNS (1.1.1.1), so it could never resolve
  `authelia.${DOMAIN}`. **Rule: when a node's upstream DNS changes,
  force-recreate every host-network container on it.** A restart is not enough.

**Version and registry drift:**

- **Traefik v3.2 broke on newer Docker Engine** ("client version 1.24 is too
  old") and looped forever. All five nodes now run `traefik:v3.7.13`.
- **Karakeep's browser image moved off gcr.io**, where anonymous pulls now
  require billing, to the same image on Docker Hub (`zenika/alpine-chrome:124`).
- **FitTrackee ships no default command.** tini printed its help text and
  exited. Pinned to `v1.3.5` with the upstream `command:`.
- **Komodo Periphery:** `core.pub` alone doesn't register a node. First connect
  needs `PERIPHERY_ONBOARDING_KEY` from Komodo's UI (one-time; blank it
  afterwards). `PERIPHERY_PRIVATE_KEY` must also be set explicitly, because
  v2 ignores the config file and falls back to a broken built-in default
  (moghtech/komodo#1425).

**Decisions:**

- **Pi-hole's web server binds IPv4 only** (`8080o`, not `8080o,[::]:8080o`).
  An IPv6 bind with no matching UFW rule was the root cause of that day's
  Pi-hole/Authelia outage. If an image upgrade brings back the `[::]` half,
  remove it again.
- **Home Assistant: OIDC only, no ForwardAuth in front**, the same as Nextcloud
  and Paperless. It uses `hass-oidc-auth` from HACS, with the local HA login
  kept as the break-glass path. HA trusts all of `${PROXY_SUBNET}`, because
  Traefik's proxied requests arrive from its bridge IP rather than the LAN IP.
  `mochapot_net` is created with that pinned subnet so the value stays true
  after a recreate.
- **Nextcloud's HSTS comes from a Traefik middleware**, not `.htaccess`, because
  Apache only ever sees HTTP and upgrades regenerate `.htaccess`. The remaining
  admin warnings are one-time `occ` settings, listed in its README.
  `allow_local_remote_servers` is required, or Nextcloud's SSRF guard blocks
  OIDC discovery to Authelia's private IP.

---

## 2026-09-16 — percolator joins the fleet: Authelia on 9091, Homepage

percolator was built as if it were the only Traefik, while sieve was built for a
Traefik on every node (entry below). As merged, sieve's admin UIs would have failed
closed. Decided: keep a Traefik per node and publish Authelia for them.

**Authelia's port 9091 is published, but only to Traefik nodes.**

- `FORWARD_AUTH_CLIENTS` in percolator's `.env.local` (default `192.168.0.10`) lists
  the nodes whose Traefik calls ForwardAuth. `firewall.sh` adds one `ufw route allow`
  per IP and rejects anything that isn't a plain address.
- Never opened to the LAN: the port is plain HTTP and also serves the login portal.
  People sign in at `https://authelia.${DOMAIN}` only.
- percolator's own Traefik keeps calling `authelia:9091` by container name.
- The session cookie is for `${DOMAIN}`, so one sign-in covers every node.

**Admin-only hosts are one list in Authelia's config**, `traefik`, `traefik-sieve`,
`pihole`, `netalertx`, `gatus`, with an `allow admins` rule and a `deny` rule for the
same list (a YAML anchor, so the two can't drift). A new node adds its admin hosts there.

**Homepage** (`homepage.${DOMAIN}`, v2.3.0) was on percolator's app list but hadn't
been built.

- Behind ForwardAuth for admins and household.
- No Docker socket and no API widgets, so it holds no credentials.
- Tiles are tracked in `homepage/dashboard/*.yaml`, mounted read-only, and use
  Homepage's own `{{HOMEPAGE_VAR_DOMAIN}}`, so there's nothing to render.

**Pi-hole gets records for percolator's apps.** percolator routes by compose labels,
which sieve's DNS generator didn't read; it now does (see "DNS follows the routes"
below).

**Bugs found by the test:**

- **Household members could open admin pages.** Authelia skips a rule whose subject
  doesn't match and carries on, so a non-admin fell through to the `*.${DOMAIN}`
  household rule. That already applied to percolator's own Traefik dashboard. Fixed
  with the `deny` rule above. Tested before and after.
- **`firewall.sh` exited silently, adding no rules,** when `.env.local` was missing or
  lacked a key: `grep` failing inside `$(…)` under `set -e -o pipefail`. Fixed with
  `|| true`.

**Tested** in a Docker sandbox: real LLDAP and Authelia, percolator's rendered
configs, a sieve-style Traefik on a separate network using sieve's unmodified
`dynamic/sieve.yml`, and ForwardAuth through the published port.

- **Anonymous:** `302` to `https://authelia.${DOMAIN}` for all four of sieve's
  protected hosts.
- **Admin session:** passes to the backend on all four.
- **Household-only session:** `403` on all four and on `traefik.${DOMAIN}`; Homepage
  opens (`200`) with all 14 tiles.
- **Authelia stopped:** sieve answers `500` (fails closed). ntfy needs no auth.
- **Config and scripts:** `authelia validate-config` passes; `docker compose config`
  passes for all 13 apps; `firewall.sh --dry-run` gives the expected rules for zero,
  one and two clients and rejects a CIDR; shellcheck is clean.
- **Homepage:** healthy with read-only config mounts; an unexpected Host header is refused.

**Not tested:** UFW itself on a real node (dry run only), real certificates, and the
Authelia login page in a browser.

## 2026-09-16 — cellar, mochaPot, grinder: three stacks added

Added `stacks/cellar/`, `stacks/mochaPot/` and `stacks/grinder/` — the first
node stacks in this repo, built to `infrastructure.md`'s post-restructure app
placement (§4), not migrated wholesale from the pre-restructure
`purrBrews-infra` build. Each node's own README states this plainly and lists
what changed. Summary here is cross-cutting decisions only.

**cellar** (192.168.0.12) — restic, Samba/NFS, Scrutiny hub, Komodo Core
+ Mongo:

- **restic replaces `backup-mirror/` outright**, not just in name. The
  2026-09-13 fleet audit's Tier 0 #1 found that `backup-mirror/mirror.sh`
  defined `mirror_source()` and never called it — nightly, silently, copying
  zero bytes, the whole time it existed. The new `restic/` scripts are real,
  runnable `restic backup` calls per source (still empty — percolator,
  sieve and mochaPot all exist in this repo now, but the actual dump
  sources aren't wired up yet, tracked in the backlog), not another
  function definition nobody invokes.
- **Scrutiny's hub and Komodo's Core + Mongo both moved here from the
  pre-restructure `silo`**, which no longer exists as a role
  (`infrastructure.md` §1's retirement note). Komodo's OIDC login is
  deliberately left off (`KOMODO_OIDC_ENABLED: "false"`) — percolator's
  Authelia exists in this repo now, but cellar isn't registered with it yet
  (see the backlog); local admin auth only until then.
- **Vaultwarden and Caddy are gone from cellar**, not lost — moved to
  percolator per the new app table. Nothing in this rebuild tries to recreate
  them.
- **NFS stays host-native**, same call the pre-restructure build made
  (containerized NFS servers still aren't recommended) — this time actually
  implemented (`nfs/setup-nfs.sh`), not just documented as a someday step.

**mochaPot** (192.168.0.13) — Home Assistant + PG, Music Assistant, Pi-hole
(secondary, DNS only), kiosk browser:

- **Home Assistant moved here from percolator** — `infrastructure.md` §4:
  "shares a failure domain with neither the app tier nor the network tier,
  the wall dashboard renders locally if percolator is down." No Traefik/
  Authelia in front of it here, unlike its old placement — the alpha-stage
  OIDC component isn't carried over either.
- **The kiosk browser is genuinely new** — cage (Wayland kiosk compositor) +
  Chromium, autologin on a dedicated `kiosk` user, not `barista`. Host-native.
- **Pi-hole here keeps a real web password**, unlike sieve's (which disables
  it in favor of Authelia's ForwardAuth) — mochaPot has no reverse proxy at
  all, so this instance's own login is its only gate.
- Jellyfin/Immich/Vikunja/n8n/FreshRSS/Mealie/Actual Budget/Stirling PDF/
  Roundcube/Traefik, everything else the pre-restructure mochaPot ran, moved
  elsewhere or were cut (`infrastructure.md` §4's "Deliberately not
  running").

**grinder** (192.168.0.14) — n8n, embedding worker, PG + pgvector, Open
WebUI, Karakeep, FitTrackee, Traccar, ESPHome dashboard, Speedtest Tracker:

- **grinder did not exist pre-restructure** — entirely new node, entirely new
  stack directory.
- **`embedding-worker` is custom-built, not a pulled image** — no published
  image exists for this project's specific "small CPU embedding API n8n
  calls" shape, so it's a small FastAPI + sentence-transformers service built
  from a `Dockerfile` in this repo. Registry image monitoring cannot track what
  `pip install` pulled into this local build — flagged
  in the node's own README, not solved here.
- **Every app gets its own dedicated Postgres** where it needs one
  (`postgres-vector` for the embedding pipeline, `postgres-fittrackee` for
  FitTrackee) — same discipline percolator's `homeassistant/docker-compose.yml`
  documents the reasoning for (a real port collision, pre-restructure, from
  sharing one Postgres layer across unrelated apps).
- **Traccar keeps its bundled H2 database**, deliberately not given its own
  Postgres like FitTrackee — high-write low-value telemetry, not judged worth
  the extra backup weight yet.
- **Open WebUI has no automated wake path to roastery's Ollama.** Ollama on
  Windows only answers once someone's logged in and the tray app is running
  (`infrastructure.md` §9) — nothing here sends the WoL packet before a chat
  request; `cellar/restic/mirror-to-roastery.sh`'s WoL-then-wait pattern is
  flagged as the reusable shape for this, not yet adapted.

**Common to all three**: `generate-secrets.sh` now uses `openssl rand -hex`,
not `-base64`, for every new secret (`infrastructure.md` §6 — the RFC 6749
§2.3.1 URL-encoding bug that broke Mealie pre-restructure is a base64-only
failure mode; hex removes the bug class rather than requiring `client_secret_basic`
to be audited per app). Traefik was added to all three the same day (each node's own
README says so under "Traefik and the native-login backdoor"), each
already pointing its `authelia-forwardauth` middleware at
`http://${PERCOLATOR_LAN_IP}:9091/api/authz/forward-auth` — percolator's
real endpoint, which now exists in this repo (see the entry above). What's
still missing is registration on percolator's side: each of these three
IPs in `FORWARD_AUTH_CLIENTS`/`firewall.sh` and in Authelia's admin-host
list, tracked in the backlog below. Until then every `*.${DOMAIN}`
hostname on these nodes 502/504s through Traefik; the direct-port
backdoor each README describes is what actually works today.

## 2026-09-15 — percolator: ingress, identity and daily apps

percolator (`.11`) runs Traefik, CrowdSec, LLDAP, Authelia + Redis, Vaultwarden,
Nextcloud + Postgres + Valkey, Immich + Postgres + Valkey, Paperless-ngx + Postgres +
Valkey, Mealie, Vikunja, Actual Budget and FreshRSS. Everything is in
`stacks/percolator/`; each app has its own README with first-run steps and an
"is it working?" checklist.

**Why these sit together:** ingress and identity on the same host as the apps means
one Docker network and routing and ForwardAuth by container name for percolator's
own apps. Other nodes' Traefik reach Authelia on its published port 9091; see the
2026-09-16 entry, which replaces this entry's original "no published auth port".

### Layout decisions

- **One `proxy` network with a fixed subnet** (`PROXY_SUBNET`, default
  `172.30.0.0/24`). Traefik and each app's web container join it; every app lists
  it as its trusted proxy. Only Traefik publishes ports (80/443). LLDAP's admin port
  is bound to `127.0.0.1` as break-glass.
- **Every database is private to its app.** Each Postgres and Valkey is on its own
  project's network only, with an app-prefixed container name. Nextcloud gets its
  own Valkey for file locking; Paperless needs one as its task broker.
- **`authelia.${DOMAIN}` is a Docker network alias of Traefik.** Apps fetch OIDC
  discovery and exchange tokens through Traefik with a valid certificate, without
  depending on LAN DNS being in place.
- **One wildcard certificate** (`${DOMAIN}` + `*.${DOMAIN}`) via Cloudflare DNS-01:
  fewer ACME orders, no inbound port 80, and app names don't appear individually in
  certificate-transparency logs.
- **Traefik `readTimeout: 0s`.** v3's 60 s default cuts off large uploads.

### Identity

- **Groups:** `purrbrews_admins` (Traefik dashboard, Mealie admin) and
  `purrbrews_household`. Authelia refuses OIDC sign-in to anyone in neither group,
  via a custom `household` authorization policy, before the app sees them.
- **`AUTH_POLICY`** (`one_factor` for now) is one variable used by every rule and
  client, so moving to two-factor is a single edit once everyone has enrolled.
- **All OIDC client secrets are generated on the node.** App plaintext and Authelia's
  PBKDF2 hash are written in the same run of `generate-secrets.sh`, since Authelia
  and all eight apps share the node. No copy step, nothing to drift.
- **Secrets are hex.** base64's `+ / =` break `client_secret_basic` in clients that
  don't URL-encode the secret, even when both sides hold the identical string.
- **Hashes are written single-quoted** so neither bash `source` nor compose's
  env-file parser expands their `$`.
- **The OIDC signing key is generated by the script** and stored as one line with
  literal `\n`, un-escaped by a double-quoted YAML string. envsubst knows nothing
  about YAML indentation, so a multi-line PEM would break the file.
- **Vaultwarden's admin token is an Argon2id hash** produced by the Authelia image;
  the plaintext stays in the secrets file for typing at `/admin`.
- **`lldap-bootstrap.sh`** creates both groups and any user, idempotently, through
  LLDAP's GraphQL API and its bundled `lldap_set_password`.

### CrowdSec: bouncer in Traefik, not the host firewall

Everything reaching percolator's apps comes through Traefik, and tunnel visitors
arrive from sieve's LAN address. A host firewall bouncer sees only that address,
which the default whitelist never bans, so it would enforce nothing. Instead:

- **The Traefik bouncer plugin** blocks by the real client address, taken from
  `X-Forwarded-For` trusted only from `SIEVE_IP`.
- **It is registered with `BOUNCER_KEY_traefik`,** using a key generated on the node;
  no `cscli bouncers add` step.
- **`updateMaxFailure: -1`:** if CrowdSec is down, Traefik keeps serving with the last
  decisions instead of blocking the household.
- **`clientTrustedIPs` = LAN,** so the bouncer never blocks LAN clients.
- **The plugin is a Traefik *local* plugin,** cloned by `traefik/prepare.sh` at a
  pinned tag and verified against its commit SHA. A catalog plugin is downloaded on
  every Traefik start. When that download failed in testing, the `crowdsec@file`
  middleware became invalid, and every route on the entry point went dark with it.

### Tooling

- **`render-configs.sh` refuses a template with an unset or empty variable.** envsubst
  silently substitutes `""` and exits 0.
- **Each template renders in its own subshell,** so one app's secrets never reach
  another's config.
- **Rendered files are 0600** unless the template opts into 0644.
- **Failures are collected and listed at the end,** and the script exits non-zero.
- **`compose.sh` checks before `up`:** it refuses REPLACE_ME placeholders, and rendered
  configs that are missing or older than their template, `.env.local` or the app's
  secrets.
- **It then creates data directories from `<app>/data-dirs`** with the owner the image
  needs, and runs `<app>/prepare.sh`. `--all` brings the node up in dependency
  order, and down in reverse.
- **It uses `sudo docker` itself;** the scripts refuse to run under sudo, so secrets
  files never become root-owned.
- **`setup-secrets.sh` appends keys** added to `local.env.example` after `.env.local`
  was created.
- **`firewall.sh`** holds the node's only UFW additions: `ufw route allow` for 80/443
  from the LAN, since published ports go through ufw-docker's FORWARD rules.

### Tested

Tested in a Docker sandbox with a stand-in `/opt/purrbrews/.env`, as a non-root ops
user with sudo.

- **Scripts:**
  - `setup-secrets.sh` ran end to end; a second run left every secrets file and
    `.env.local` byte-identical.
  - `render-configs.sh` refused a template with an emptied `SIEVE_IP` and rendered
    the rest.
  - `compose.sh` refused a stale render and a failed `prepare.sh`.
  - shellcheck is clean.
- **Compose and config:**
  - `docker compose config` passes for all 12 apps.
  - `authelia validate-config` passes on the rendered configuration.
  - `authelia crypto hash validate` matched a generated client secret to its hash.
- **Identity:**
  - `lldap-bootstrap.sh` ran as a dry run, then created the groups and user, and a
    re-run changed nothing.
  - Authelia first-factor login as the new user worked. The Traefik dashboard
    redirected to Authelia and opened after login.
  - Container DNS resolved `authelia.${DOMAIN}` to Traefik on `proxy`.
- **OIDC:** all 8 clients authenticated at Authelia's token endpoint with their
  generated secret and configured auth method (`invalid_grant` on a dummy code).
  A wrong secret gave `invalid_client`.
- **Traefik and CrowdSec:**
  - The local plugin loaded.
  - With CrowdSec unreachable, Traefik kept serving.
  - The access log was written.
  - The Nextcloud `.well-known/caldav` redirect worked.
- **Apps:**
  - Vaultwarden's `/admin` accepted the password against the Argon2id token and
    rejected a wrong one.
  - Every container started and passed its healthcheck where it has one.
  - Nextcloud installed (34.0.4) with the proxy settings and Redis locking applied.
  - Immich answered `/api/server/ping`.
  - Paperless ran migrations and offered Authelia sign-in.
- **Bugs found and fixed by the test:**
  - `envsubst --variables` needs its input as an argument, so the unset-variable
    guard was silently checking nothing.
  - Postgres 18 couldn't start under a root-owned 0700 parent directory; it is now
    created as 999:999.
  - Paperless's server binds `::` by default and dies on a kernel with IPv6
    disabled; it now binds `0.0.0.0`.
- **Not tested (no real domain or certificate in the sandbox):**
  - ACME issuance.
  - Browser OIDC round-trips for each app.
  - Actual Budget and Vikunja startup against a trusted Authelia certificate. Both
    retried against the sandbox's self-signed certificate, as expected.
  - CrowdSec hub download and a real ban through the tunnel.
  - Nextcloud's `user_oidc` install.

## 2026-09-15 — A Traefik on every node; SSO stays central

Each node runs its own Traefik for its own apps, instead of one Traefik on percolator
fronting the fleet. The goal is blast radius: a bad route, a broken proxy or a dead
node takes down that node's pages only.

**What stays shared: login.**

- Authelia runs once, on percolator. Every node's Traefik uses a ForwardAuth
  middleware against it, so there's still one SSO session across `${DOMAIN}`.
- **Accepted trade-off:** if percolator is down, protected UIs on other nodes fail
  closed (`500`). Anything with its own accounts (ntfy) or no UI (DNS, DHCP, the
  tunnel, alerting) is unaffected.
- On sieve, loopback SSH forwarding opens the UIs without SSO, as break-glass.

**The ForwardAuth hop must be direct:** `http://<percolator>:9091/api/authz/forward-auth`.

- Through percolator's Traefik (`https://auth.${DOMAIN}/…`), the second proxy rewrites
  or drops `X-Forwarded-Method/Host/Uri` and Authelia returns `400`.
- Authelia also refuses targets with an `http` scheme, so every protected router is
  HTTPS with a real certificate.
- Tested on sieve against a stub auth server: unauthenticated requests are redirected
  to login, a valid session passes, and the auth call carries `X-Forwarded-Method`,
  `Proto=https`, `Host` and `Uri`.

**Per node:**

- Certificates by DNS-01. No two nodes request the same set: percolator holds the
  `*.${DOMAIN}` wildcard, other nodes use one certificate per router. Otherwise they
  share Let's Encrypt's five-identical-certificates-a-week limit, and a couple of
  rebuilds exhaust it.
- Routes in file-provider YAML read as Go templates (`{{ env "DOMAIN" }}`), so there's
  no render step. No Docker socket.

**DNS follows the routes, not a wildcard.** sieve's
`setup-secrets.sh` reads every node's router rules and writes
`address=/<name>.${DOMAIN}/<node IP>` for Pi-hole, so a route and its DNS record
can't drift apart. It reads sieve's `traefik/dynamic/*.yml`, percolator's
`traefik/config/*.template` and compose labels. Tested with percolator's stack in
the repo: its 11 names resolve to `.11`, and sieve's 5 to `.10`. The remaining manual step: re-run it on
sieve after adding a route. The first version also matched an example `Host(...)` in
a comment; it now reads only `rule:` lines.

## 2026-09-15 — sieve: the network stack

sieve (.10) runs the six apps that keep the house online and report problems —
Pi-hole (DNS + DHCP), Unbound, cloudflared, ntfy, Gatus and NetAlertX — plus its own
Traefik (entry above). It runs nothing else, so app work never reboots the network.

**DNS: Pi-hole → Unbound, on the same host, with no published resolver port.**

- Unbound sits on its own bridge (`sieve_dns`, fixed `172.31.53.2`). Pi-hole uses host
  networking and reaches it over that bridge, so the resolver is unreachable from the
  LAN by construction. That avoids a firewall rule or a 5335 remap.
- Unbound's access list uses the most-specific match, whatever the order. The image
  already allows `192.168.0.0/16` and `172.16.0.0/12`, so the overrides must be more
  specific: allow the bridge gateway `/32`, refuse the bridge `/28`, refuse the LAN
  `/24`. A `0.0.0.0/0 refuse` would lose to the image's `/16` allow.
  Tested: the host is answered; another container on the bridge gets `REFUSED`.
- Unbound is not `read_only`: it rewrites `root.key` on trust-anchor rollovers.

**Pi-hole is configured entirely by `FTLCONF_*` variables.** Nothing is clicked in the
UI, and a rebuilt container is identical.

- Upstream, DHCP range, 7-day lease and the NTP server (off) are in the compose file.
  Static leases and host names for every node come from `init/purrbrews-mac.sh`,
  generated into `.env.local` by `setup-secrets.sh`.
- App host names come from every node's Traefik routers (entry above).
- `filter-AAAA` stops IPv6-preferring clients using a public AAAA to bypass a local
  record.
- Tested against a fake upstream: a local record answers A, AAAA is filtered, and a
  `server=/name/#` exemption forwards as expected.
- **DHCP starts off** (`PIHOLE_DHCP_ACTIVE=false`) and is handed over deliberately.
  - Two DHCP servers on one LAN is the failure to avoid.
  - `67/udp` must be open from *any*: a client's first request comes from `0.0.0.0`.
  - The 7-day lease gives ~3.5 days of grace; the router's DHCP stays configured but
    off, as break-glass.

**Admin UIs have no login of their own; sieve's Traefik + Authelia is the gate.**

- Pi-hole (8080) and NetAlertX (20211) run on host networking with auth disabled.
  `firewall.sh` opens those ports to `sieve_edge` only (Traefik and Gatus), never the
  LAN. Gatus publishes no port at all.
- NetAlertX has unauthenticated-RCE history, so its API port (20212) gets no rule, and
  none of these UIs may ever be routed through the tunnel.
- NetAlertX settings are forced with `APP_CONF_OVERRIDE` (subnet + interface, password
  off, `BACKEND_API_URL=/server`, so only 20211 needs proxying). Tested: all show as
  overridden by env.
- ntfy is served on the LAN by sieve's Traefik, and outside by the tunnel. Phones at
  home get alerts even with the WAN down.

**Tunnel and notifications.**

- cloudflared is token-based and remotely managed. Routes are in the Cloudflare
  dashboard, recorded in `cloudflared/README.md`, because nothing else captures them.
- Two lessons are written in advance for routes to a node's Traefik:
  - use `https://…:443`, since `http://:80` loops on Traefik's redirect;
  - set the Origin Server Name, or TLS fails on Traefik's default certificate.
- ntfy is public through the tunnel with `deny-all`, no sign-up, and declarative users,
  ACLs and tokens (`NTFY_AUTH_*`, re-applied each start). Passwords are bcrypt-hashed by
  ntfy's own `user hash` via `docker run`. Tested: Gatus's token can publish but not
  read; anonymous access gets 403; an extra read-only user works.

**Alerting in three layers**, since a monitor can't report its own death:

1. Gatus → self-hosted ntfy for routine alerts.
2. Gatus → public ntfy.sh (a random 24-hex topic) when the failure is the delivery
   path itself (ntfy, the tunnel).
3. Gatus pings healthchecks.io every 5 min, and healthchecks.io alerts on silence (sieve,
   Gatus or the WAN dead).

Gatus reads its tracked config and substitutes `${VARS}` itself, so no secret is
rendered to disk. It alerts straight to the ntfy container rather than through
Traefik, and checks the certificate plus the SSO answer on a real `https://` request
resolved through Pi-hole. Tested: failing checks delivered alerts to the ntfy topic. The
ntfy.sh path couldn't be exercised from the sandbox (TLS interception), so the
deliberate-break test is in the backlog.

**Bug found while testing:** a Gatus HTTP check with only `[STATUS] < 400` passed
against a stopped service, because a refused connection reports status 0. Every
HTTP check now also requires `[CONNECTED] == true`, and `stacks/README.md` says so.

**Scripts.**

- `setup-secrets.sh` appends keys that are new in `local.env.example` to an existing
  `.env.local`. Without that, a key added later silently stays unset on nodes that
  already have the file.
- It detects the LAN interface, builds Pi-hole's host lists, creates data directories
  and calls `generate-secrets.sh`.
- Both scripts refuse to run as root (root-owned files break the next run) and use
  sudo only where needed.
- Secrets are hex (`openssl rand -hex`). Values are single-quoted, because bcrypt
  hashes contain `$`.
- `compose.sh` loads `/opt/purrbrews/.env`, `.env.local` and the app's secrets, runs
  Docker via sudo, creates `sieve_edge` with its fixed subnet, and supports `all`.
- `firewall.sh` holds every rule (`ufw allow` for host-network apps, `ufw route allow`
  for published ports) and supports `--dry-run`.

**Tested** in a Debian container with Docker, as a non-root ops user:

- `setup-secrets.sh` from nothing, then re-run: byte-identical files;
- `docker compose config` for all six apps;
- all seven containers up (Pi-hole, NetAlertX, ntfy and Traefik healthy);
- Traefik routing and ForwardAuth against a stub auth server;
- every `firewall.sh` rule accepted by `ufw --dry-run`;
- shellcheck clean.

**Not tested:**

- real recursion to the root servers (the sandbox has no outbound DNS);
- a real tunnel;
- Let's Encrypt issuance (the sandbox intercepts TLS);
- real Authelia;
- ntfy.sh delivery;
- ICMP checks;
- DHCP on a real LAN;
- NetAlertX scan results.

The bring-up table in `stacks/sieve/README.md` has a check for each.

## 2026-09-15 — Public repository, zero secrets in transit

The GitHub repository is **public**. Nodes clone and pull it anonymously over https, so
there are no tokens, deploy keys or credential helpers anywhere.

- **Secrets are generated on each node** by `generate-secrets.sh` into gitignored
  `secrets.env.local` files. They are never committed, not even encrypted.
- **The bootstrap container serves only public material:** scripts, public SSH keys and
  fleet settings. It needs no password.
- **The ops user's sudo password** is typed at each node's console, or generated with
  `--yes`. A password hash is accepted only from a local root-only settings file, never
  from the bootstrap server.
- **Guards:**
  - `purrbrews-init.sh` rejects a `GITHUB_TOKEN`, a non-https `REPO_URL` and credentials
    embedded in the URL.
  - The bootstrap container refuses to start, and `bootstrap.sh` refuses to continue, if
    the served settings contain `OPS_PASSWORD_HASH` or `GITHUB_TOKEN`.

## 2026-09-15 — Fleet naming, static addressing, cloned MACs

**Nodes:** sieve .10, percolator .11, cellar .12, mochaPot .13, grinder .14 on
192.168.0.0/24. `.1`–`.5` are reserved for routers and switches.

**Every node carries a cloned MAC** in the same NetworkManager profile as its static IP,
so both change together in one link change.

- **Derivation:** the MAC is derived from the node name as `02:` + the first 5 bytes of
  sha256("purrbrews:<lower-case name>").
  - It is locally administered, so it can't collide with a vendor MAC.
  - It is stable across reinstalls and NIC swaps, and needs no record kept.
  - `NODE_MACS` overrides it per node.
- **Rejected before anything changes:** duplicate names, IPs and MACs; multicast MACs;
  unknown node names; Wi-Fi interfaces.
- **Wake-on-LAN** still uses the burned-in MAC.
- **Tooling:** `init/purrbrews-mac.sh` lists the MACs (table, Pi-hole, dnsmasq, CSV),
  compares expected, current and burned-in MACs on a node, and re-applies them.

**How the network switch runs:**

- It runs detached (`systemd-run`), so a dropped SSH session can't interrupt it.
- **Success** requires all of these:
  - the new address and MAC are on the link;
  - the default route goes via `GATEWAY`;
  - the gateway answers.
- **Otherwise** the old profile and MAC are restored within 60 s.
- **Re-runs** build `purrbrews-<iface>-next` and swap it in only after it has proven
  itself.
- A second run while a switch is in progress is refused.

## 2026-09-15 — Bootstrap served from the workstation

`bootstrap/` builds `purrbrews-bootstrap`, an nginx 1.29.8-alpine container for Docker
Desktop. It serves:

| Path | Content |
|---|---|
| `/bootstrap.sh` | the node one-liner; base URL injected per request |
| `/files/*` + `SHA256SUMS` | `init/`, baked in at build |
| `/keys/authorized_keys` | live from `bootstrap/data/` |
| `/config/purrbrews-init.env` | live fleet settings, no secrets |

**TLS pinning:**

- A self-signed key lives in a named volume, so it survives rebuilds.
- Nodes pin it on first contact: strictly with `PB_PIN`, or trust-on-first-use with a
  confirmation prompt.
- The pin is stored on the node, so the hourly key sync is pinned too.

**Container hardening:** read-only root filesystem, all capabilities dropped except
those nginx needs, `no-new-privileges`.

**Key sync exit codes:**

| Code | Meaning | Unit result |
|---|---|---|
| 0 | ok | success |
| 75 | source unreachable (workstation asleep); nothing changed | success |
| 1 | TLS pin mismatch or any other error | failed |

Accepted trade-off: revoking a key takes effect once the workstation is awake.

## 2026-09-15 — `init/`: one-command node provisioning

`init/purrbrews-init.sh` takes a fresh Debian 13 install to "only the stacks are left".
It runs as named, individually re-runnable steps.

**Security model:**

- SSH is key-only, with no root login, via a validated `sshd_config.d` drop-in.
- The drop-in refuses to apply until a key is installed.
- `barista` reaches root only through a password-gated `sudo`, and is never in the
  `docker` group.

**Settings:** one KEY=value file, parsed and never sourced. It tolerates CRLF line
endings and a UTF-8 BOM.

**Timers:** systemd timers with `Persistent=true`, so a missed daily pull runs at boot.
Pulls are fast-forward only, refuse a dirty tree, never restart containers, and can ping
healthchecks.io.

**Firewall:** UFW rules are additive, so re-runs never wipe per-app rules. SSH is allowed
from the LAN only. ufw-docker is pinned to a release tag and verified by SHA-256.

**Also:** Docker log rotation (10 MB × 3), a journal size cap, masked suspend targets,
and a generated `/opt/purrbrews/.env` (NODE, NODE_IP, TZ, PUID/PGID, paths).

**Tested** in systemd Debian 13 containers, end to end through the bootstrap container:

- **Idempotency:** a full run, then a re-run, left config files and firewall rules
  byte-identical.
- **SSH:** key login works; password and root logins are refused; a key revoked at the
  source is locked out after one sync.
- **Key sync edge cases:** an unreachable source leaves keys unchanged; a pin mismatch is
  a hard failure.
- **Pull timer** fast-forwards, and refuses on a dirty tree.
- **Network switch on a NetworkManager-managed link behind a simulated gateway:**
  - DHCP → static + cloned MAC works; re-runs are no-ops.
  - A MAC change swaps in cleanly.
  - A wrong gateway rolls back in about 65 s.
- **Bugs found and fixed while testing:**
  - Re-runs deleted the live network profile before building the new one.
  - Overlapping runs could apply a wrong gateway.
  - After a rollback, the old MAC was not restored.
  - Terminal detection accepted a tty that couldn't be opened.
  - A leaked `umask 077` made later config files root-only.
- **Not yet tested:** real hardware (including the ifupdown → NetworkManager path on a
  netinst install) and Docker Desktop on Windows.

## 2026-09-15 — Repository conventions

- **Line endings:** `* text=auto eol=lf`, since the repo is authored on Windows and
  deployed to Linux.
- **`.gitignore`:** names specific sensitive files rather than using blanket patterns
  that could hide legitimate files.
- **No placeholder folders:** node and app directories appear with their first real file.
- **Default branch:** `main`.
