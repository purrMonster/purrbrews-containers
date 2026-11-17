# Carry-over map

Where every app and every part of the old repo went in the 2026-11 rebuild,
app by app. "Old" paths are as they were on `main` at `375c274` (tag
`freeze-2026-10` is the pre-move state); everything not carried is kept, unedited,
under [`deprecated/`](../deprecated/ABOUT.md) at its old path.

Status words:

- **Carried**: moved, works as before apart from the layout.
- **Changed**: moved and edited; the last column says what.
- **Merged**: several per-node copies became one folder.
- **New**: written in this rebuild.
- **Archived**: in `deprecated/`, not used. The last column says what replaces it.
- **Source**: archived, but the planned replacement should be built from it.

Nothing in this table has run on a node since the move. "Not run" in the
[migration plan](migration-plan.md) means exactly that.

## Apps

### network

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| Unbound | `stacks/sieve/unbound` | `stacks/network/unbound` | sieve | Carried | LAN addresses in `access-control.conf` moved to `192.168.1.x` |
| Pi-hole (primary, DHCP) | `stacks/sieve/pihole` | `stacks/network/pihole` | sieve | Changed | `enable-dhcp.sh` moved in beside it and now checks `RESOLVER=primary` instead of the host name. DHCP pool is `192.168.1.50`–`.250`. The handover is from the Humax router this time |
| Pi-hole (secondary) | `stacks/mochaPot/pihole` | `stacks/network/pihole-secondary` | mochaPot | Carried | Renamed so app names stay unique. Still `pihole-mochapot.${DOMAIN}` |
| cloudflared | `stacks/sieve/cloudflared` | `stacks/network/cloudflared` | sieve | Carried | Routes still to be added in the Cloudflare dashboard (old Backlog: opencloud, radicale, cafe, meow). `llm` is admin-only and stays off the tunnel |
| NetAlertX | `stacks/sieve/netalertx` | `stacks/network/netalertx` | sieve | Carried | |
| CrowdSec | `stacks/percolator/crowdsec` | `stacks/network/crowdsec` | percolator | Carried | |
| Traefik, sieve | `stacks/sieve/traefik` | `stacks/network/traefik-edge` | sieve | Carried | Renamed. File-provider routes, as before |
| Traefik, percolator | `stacks/percolator/traefik` | `stacks/network/traefik-ingress` | percolator | Carried | Renamed |
| Traefik, the other nodes | `stacks/{cellar,mochaPot,grinder}/traefik` | `stacks/network/traefik` | cellar, mochaPot, grinder | Merged | grinder's copy is the base. Now trusts sieve's forwarded headers on every node and has a second middleware, `authelia-forwardauth-basic`, for service accounts. **Check on mochaPot**: its provider is now scoped to `proxy`, and its three apps are host-networked |
| Traefik, roastery (native Windows) | `stacks/roastery/traefik` | | | Archived | Fronted the local LLMs; LiteLLM's route is on grinder's Traefik |

### identity and mail

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| LLDAP | `stacks/percolator/lldap` | `stacks/identity/lldap` | percolator | Changed | `lldap-bootstrap.sh` moved in beside it and reads the node's `.env.local` through `_lib`. Service accounts to create: `scottishfold`, `pixiebob`, `sphynx`, and the LLM accounts in `llm_api_group` |
| Authelia | `stacks/percolator/authelia` | `stacks/identity/authelia` | percolator | Changed | `ollama.${DOMAIN}` is now `llm.${DOMAIN}` and `ollama_api_group` is `llm_api_group`. Two-factor is still off (`AUTH_POLICY=one_factor`) |
| Mail relay | `stacks/percolator/mail-relay` | `stacks/mail/mail-relay` | percolator | Carried | Never ran on the old fleet: needs the Purelymail app password. Paperless, Vikunja and Vaultwarden refuse to start until it has run once |

### apps (the household's)

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| Vaultwarden | `stacks/percolator/vaultwarden` | `stacks/apps/vaultwarden` | percolator | Carried | Needs the relay bundle |
| OpenCloud | `stacks/percolator/opencloud` | `stacks/apps/opencloud` | percolator | Carried | Upgrade gate: a fresh install records its version itself |
| Radicale | `stacks/percolator/radicale` | `stacks/apps/radicale` | percolator | Carried | Needs `scottishfold` in LLDAP |
| Immich | `stacks/percolator/immich` | `stacks/apps/immich` | percolator | Changed | `IMMICH_ML_URL` now points at grinder. v3.3.3 was merged but never deployed on the old fleet |
| Paperless-ngx | `stacks/percolator/paperless` | `stacks/apps/paperless` | percolator | Carried | Needs the relay bundle |
| Mealie | `stacks/percolator/mealie` | `stacks/apps/mealie` | percolator | Carried | |
| Vikunja | `stacks/percolator/vikunja` | `stacks/apps/vikunja` | percolator | Carried | Needs the relay bundle |
| meowGram | `stacks/percolator/meowgram` | `stacks/apps/meowgram` | percolator | Carried | 2.0.0 is pinned and was never rolled out. Starts empty (owner, 2026-11-17), so there is nothing to dump first |
| Actual Budget | `stacks/percolator/actualbudget` | `stacks/apps/actualbudget` | percolator | Carried | |
| FreshRSS | `stacks/percolator/freshrss` | `stacks/apps/freshrss` | percolator | Carried | |
| Homepage | `stacks/percolator/homepage` | `stacks/apps/homepage` | percolator | Carried | Tiles not reviewed for the new hosts (`llm`) |
| purrCafe | `stacks/percolator/purrcafe` | `stacks/apps/purrcafe` | percolator | Carried | Never ran on the old fleet |
| Karakeep | `stacks/grinder/karakeep` | `stacks/apps/karakeep` | grinder | Carried | Old Backlog: check the phone share sheet signs in through the host name |
| FitTrackee | `stacks/grinder/fittrackee` | `stacks/apps/fittrackee` | grinder | Carried | |
| Traccar | `stacks/grinder/traccar` | `stacks/apps/traccar` | grinder | Carried | |

### home

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| Home Assistant | `stacks/mochaPot/homeassistant` | `stacks/home/homeassistant` | mochaPot | Carried | `trusted_proxies` must list the new `proxy` subnet and sieve's new address. Voice (phase 9) adds the Wyoming integrations |
| Music Assistant | `stacks/mochaPot/musicassistant` | `stacks/home/musicassistant` | mochaPot | Carried | |
| ESPHome | `stacks/grinder/esphome` | `stacks/home/esphome` | grinder | Carried | |
| Kiosk (host-native) | `stacks/mochaPot/kiosk` | `stacks/home/kiosk` | mochaPot | Carried | Listed in mochaPot's `TOOLS` so its template still renders |
| Voice: Whisper, Piper, satellites | | (planned: `stacks/voice/…`) | sieve, percolator, cellar | Not written | Migration plan, phase 9 |

### automation and ai

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| n8n | `stacks/grinder/n8n` | `stacks/automation/n8n` | grinder | Carried | Workflows that called the local model need the new address (they live in n8n, not here) |
| pgvector | `stacks/grinder/postgres-vector` | `stacks/automation/postgres-vector` | grinder | Carried | |
| Embedding worker | `stacks/grinder/embedding-worker` | `stacks/automation/embedding-worker` | grinder | Carried | Its own small model on the CPU; never depended on roastery |
| pourOver | `stacks/grinder/pourover` | `stacks/automation/pourover` | grinder | Changed | Talks to `llm.${DOMAIN}` and asks for the model `default`. **Check**: it was written against llama-swap; try its planning prompt against the cloud model before relying on it. Optional in `fleet.json` |
| LiteLLM | | `stacks/ai/litellm` | grinder | New | The one door to a cloud model. Set up for any OpenAI-compatible endpoint until the provider is chosen: base URL, model id and API key. No master key, no database: reachable only on grinder's `proxy` network and through Authelia |
| Open WebUI | `stacks/grinder/openwebui` | `stacks/ai/openwebui` | grinder | Changed | Points at LiteLLM instead of Ollama on roastery. Kept as the chat page; replace it if something lighter is wanted |
| Immich ML | `stacks/roastery/immich-ml` | `stacks/ai/immich-ml` | grinder | Changed | CPU image instead of CUDA, model cache under `DATA_DIR`, port 3003 open to percolator only. Must stay on Immich's version |
| llama-swap, game mode | `stacks/roastery/llama-swap`, `game-mode` | | | Source | Come back behind LiteLLM when there is a GPU again |

### monitoring and fleet management

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| Gatus | `stacks/sieve/gatus` | `stacks/monitoring/gatus` | sieve | Changed | New addresses; a check for `llm`. Still to add: immich-ml's port |
| ntfy | `stacks/sieve/ntfy` | `stacks/monitoring/ntfy` | sieve | Carried | |
| Speedtest Tracker | `stacks/grinder/speedtest-tracker` | `stacks/monitoring/speedtest-tracker` | grinder | Carried | |
| Komodo Core | `stacks/cellar/komodo` | `stacks/fleet-management/komodo` | cellar | Carried | |
| Komodo Periphery | `stacks/{sieve,percolator,mochaPot,grinder}/komodo-periphery` | `stacks/fleet-management/komodo-periphery` | every node but cellar | Merged | The four Linux copies were identical |
| Scrutiny hub | `stacks/cellar/scrutiny` | `stacks/fleet-management/scrutiny` | cellar | Changed | A second disk is optional now (cellar has one) |
| Scrutiny collector | `stacks/{sieve,percolator,mochaPot,grinder}/scrutiny-collector` | `stacks/fleet-management/scrutiny-collector` | every node but cellar | Merged | One file for one or two disks. mochaPot's SanDisk override moved to `nodes/mochaPot/scrutiny-collector.yaml`. **Check**: the `/dev/null` stand-in for a missing second disk, and the default `collector.yaml` |
| persianPerch | `stacks/cellar/persian-perch` | `stacks/fleet-management/persian-perch` | cellar | Changed | roastery is no longer an allowed source. Its unused roastery token is still generated. Optional; never ran |
| Windows agents | `stacks/roastery/{komodo-periphery,scrutiny-collector}` | | | Archived | |

### backup

| App | Old path | New path | Runs on | Status | What changed, what is left |
|---|---|---|---|---|---|
| restic, the hub | `stacks/cellar/restic` | `stacks/backup/restic` | cellar (`BACKUP_HUB=true`) | Changed | Paths and units only. **Not usable**: still written around a repository on roastery (wake-on-LAN, an rclone remote named `roastery`). Phase 5 |
| restic, the nodes | `stacks/<node>/restic/secrets.conf` | same folder, `secrets.client.conf` | every node (`TOOLS`) | Merged | `secrets.hook` picks the hub's or a client's spec |
| Wake roastery | `stacks/cellar/restic/wake-roastery.*` | | | Archived | Nothing to wake |
| Backup target | `stacks/roastery/backup-target` | | | Source | The Linux equivalent on cellar is phase 5 |
| Samba | `stacks/cellar/smb` | `stacks/backup/smb` | cellar | Carried | Optional; unused, port closed, `latest` tag. Decide or drop |
| NFS (host-native) | `stacks/cellar/nfs` | `stacks/backup/nfs` | cellar | Carried | |
| flask, the recovery kit | `stacks/roastery/flask`, `docs/flask.md` | | | Source | Built with PowerShell on roastery. Rebuild from americano; the kit's contents list is still right |

## Everything that is not an app

| Part | Old path | New path | Status | Notes |
|---|---|---|---|---|
| Shared scripts | `stacks/_lib` | same | Changed | Find apps by name and nodes under `nodes/`; `TOOLS`, `BACKUP_HUB`, `this_node_dir`, `apply_spec_file` are new |
| PowerShell twin | `stacks/_lib/purrbrews.ps1`, `stacks/roastery/*.ps1` | | Archived | Only roastery used it |
| Node definitions | `stacks/<node>/{node.conf,local.env.example,*.sh,README.md}` | `nodes/<node>/` | Changed | The READMEs are the old ones with a banner and fixed paths: rewrite as each node comes up |
| Fleet facts | `stacks/fleet.env` | same | Changed | New LAN, no roastery, repository on cellar |
| Fleet policy | `fleet.json` | same | Changed | Five nodes |
| Deploy runner | `scripts/fleet.py`, `scripts/images.py` | same | Changed | Paths only |
| Bootstrap container | `bootstrap/` | | Archived | Replaced by [purrbrews-bootstrap](https://github.com/purrMonster/purrbrews-bootstrap) (owner's decision) |
| Node init | `init/purrbrews-init.sh` | | Source | purrbrews-bootstrap covers hostname, timezone, packages, user, keys, SSH, power, journald, Docker and the firewall. The rest becomes its payload: migration plan, phase 1 |
| Network apply, derived MACs | `init/lib/net-apply.sh`, `node-mac.sh`, `init/purrbrews-mac.sh` | | Source | For the payload: static address with rollback, MAC from the node name |
| Fetch-only timer | `init/lib/purrbrews-pull.sh` | | Source | For the payload. Its test left `tests/` with it |
| SSH key sync | `init/lib/sync-ssh-keys.sh` | | Archived | purrbrews-bootstrap's own sync replaces it |
| LAN DNS for a client | `init/use-lan-dns.py` | | Source | Still useful on a node after DHCP moves to Pi-hole |
| roastery init | `init/roastery-init.ps1`, `init/lib/windows-runtime.ps1` | | Archived | |
| Tailscale | `tailscale/` | same | Carried | Policy has the new addresses and no roastery web grant. The join step was part of init: phase 10. The Remote Desktop grant is still there |
| Tests | `tests/` | same | Changed | Adapted, with new layout checks. The init, flask, roastery and PowerShell tests are archived with their subjects |
| CI | `.github/workflows/tests.yml` | same | Changed | No Windows jobs |
| Dependabot | `.github/dependabot.yml` | same | Changed | Paths. The eleven open PRs target the old layout: close them and let it reopen |
| Operations, image upgrades | `docs/operations.md`, `docs/image-upgrades.md` | same | Changed | Small corrections only |
| Map, README, project card | `docs/MAP.md`, `README.md`, `PROJECT.md` | same names | New | The old ones are in `deprecated/` |
| Runbook | `runbook.md` | `deprecated/runbook.md` | Archived | 78 entries of reasons. Comments in the code that say "runbook, 2026-09-…" or "2026-10-…" mean that file. The new `runbook.md` starts on 2026-11-16 |
| Audit, flask, LLM consumer docs | `docs/network-audit.md`, `flask.md`, `llama-swap-consumption.md` | | Archived | |
| Agent rules | `AGENTS.md` | same | Changed | Pointers to the new layout; the rules themselves are untouched |

## Counts

- 49 app folders now, each with one home (46 with a compose file, plus restic, NFS and the kiosk); 54 app slots across the five `node.conf` files.
- Three Traefik folders instead of six, one Periphery instead of five, one collector instead of five.
- 2 new stacks (LiteLLM; Immich ML rewritten for the CPU), 1 planned (voice).
