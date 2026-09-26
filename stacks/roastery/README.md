# roastery

**The Windows workstation**: Ryzen 5 5000-series, RTX 3080 10 GB, 16 GB, Windows 11
with Docker Desktop (WSL2 backend). A gaming rig that does the fleet's GPU work on
the side, so not a fleet node: no `init/purrbrews-init.sh`, no `/opt/purrbrews`, no
`DATA_DIR`, and it sleeps between uses.

| What | How | Where |
|---|---|---|
| [purrbrews-bootstrap](../../bootstrap/README.md) | container | serves node setup on `:8443` |
| immich-ml | `./compose.ps1 immich-ml up -d` | `:3003`, percolator only (Windows Firewall) |
| Komodo Periphery | `./compose.ps1 komodo-periphery up -d` | dials out to cellar |
| [Traefik → Ollama](traefik/README.md) | `.\traefik\start.ps1`, native | `ollama.${DOMAIN}`, admins, via Authelia |
| restic mirror | nothing here; cellar pushes to it | `stacks/cellar/restic` |

## Scripts

The same scripts as every other node, plus PowerShell twins so nothing needs WSL or
Git Bash. Both read `node.conf` and the same env files (`stacks/fleet.env`, then
`.env.local`, then the app's `secrets.env.local`).

| PowerShell | bash (Git Bash + python3) | Does |
|---|---|---|
| `.\setup-secrets.ps1` | `./setup-secrets.sh` | `.env.local` from the example, prompts, render |
| `.\render-configs.ps1` | `./render-configs.sh` | `*.template` → rendered files (Traefik's config) |
| `.\compose.ps1 <app> …` | `./compose.sh <app> …` | `docker compose` with the env files and the pre-`up` checks |

The PowerShell side lives in [`../_lib/purrbrews.ps1`](../_lib/purrbrews.ps1) and
mirrors the bash side; change one, change the other.

## immich-ml

`immich-machine-learning` on the 3080, so percolator's Immich doesn't do faces and
smart search on its CPU. **The tag must match `immich-server` on percolator
exactly**; bump both together, after reading Immich's release notes.

**GPU first.** Docker Desktop has no GPU toggle; it just works once the WSL2 backend
is on, the Windows NVIDIA driver is ≥ 545 (CUDA ≥ 12.3) and `wsl --update` has run.
Check before the first bring-up:

```powershell
docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi
```

**Then the firewall, which is the only protection it has.** The container has no
authentication at all, and a firewall inside WSL does nothing: Docker Desktop's
engine runs in its own VM. From an elevated PowerShell:

```powershell
New-NetFirewallRule -DisplayName "immich-ml (percolator only)" `
  -Direction Inbound -Protocol TCP -LocalPort 3003 `
  -RemoteAddress 192.168.0.11 -Action Allow
```

Windows allows a packet if *any* rule does, so check a broad Docker or vpnkit rule
isn't already letting everyone in:

```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*docker*" -or $_.DisplayName -like "*vpnkit*" } | Get-NetFirewallPortFilter
```

Then `.\compose.ps1 immich-ml up -d`, put `http://<roastery IP>:3003` in
percolator's `IMMICH_ML_URL`, and confirm it under *Administration → Settings →
Machine Learning* in Immich.

**Is it working?**

- `curl http://<roastery IP>:3003/ping` works from percolator, and fails from
  anywhere else. The second half matters as much as the first.
- Immich's *Jobs* page shows Smart Search and Face Detection moving.
- `docker logs immich-machine-learning` shows the GPU in use, not a silent CPU
  fallback (which looks like "working", only slower).

Set job concurrency in Immich's *Job Settings*; the default can be more than a
shared gaming GPU wants. When roastery is asleep, indexing just waits.

## Komodo Periphery

Copy cellar's `/srv/data/komodo/keys/core.pub` to `komodo-periphery\keys\core.pub`,
put an onboarding key from Komodo's UI in `.env.local` for the first connect, then
`.\compose.ps1 komodo-periphery up -d`. Leave the key empty once roastery shows up
as a Server. No Scrutiny collector: Docker Desktop doesn't pass raw Windows disks
through to smartctl.
