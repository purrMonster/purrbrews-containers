# roastery

Windows 11 workstation (Ryzen 5 5000-series, RTX 3080 10 GB, 16 GB DDR4) —
gaming rig doing on-demand GPU work on the side, not dedicated server
hardware (`infrastructure.md` §2/§4). Unlike every Debian fleet node, this
one isn't provisioned by `init/purrbrews-init.sh`, has no `/opt/purrbrews`,
no `$DATA_DIR` convention, and runs Docker Desktop (WSL2 backend) instead of
bare Docker. Scripts here are bash, run from WSL2 or Git Bash, same
`chmod +x` NTFS caveat as every other node.

Per `infrastructure.md` §4, roastery's full role is Ollama (a native Windows
service, not containerized — see its own hard-won-constraints note in §9),
`immich-machine-learning` (this directory), and the restic backup mirror
(already exists as `stacks/cellar/restic/mirror-to-roastery.sh`, which runs
*on cellar* and connects out to roastery — nothing to build here for that).
Only `immich-ml` is a docker stack, which is what this directory holds.

| | |
|---|---|
| Image | `ghcr.io/immich-app/immich-machine-learning:v3.2.1-cuda` |
| Depends on | percolator's `immich-server` at the same version (`stacks/percolator/immich/`) |
| Port | `3003`, restricted by Windows Firewall (see below) — **not** by Docker |
| Data | `immich-ml/model-cache/` (downloaded model weights, gitignored) |
| Secrets | none |

## GPU prerequisites

GPU support on Docker Desktop for Windows/WSL2 is automatic once three
things hold — there is **no GPU-support toggle** in Docker Desktop's
Settings UI (checked directly against docs.docker.com/desktop/features/gpu/;
if you go looking for one, you won't find it):

1. WSL2 backend enabled — *Settings → General → "Use the WSL 2 based
   engine"* (on by default in current Docker Desktop versions).
2. A current NVIDIA driver (**≥545**, CUDA ≥12.3) installed on **Windows
   itself**, not inside WSL2, supporting WSL2 GPU Paravirtualization. Check
   with `nvidia-smi` in PowerShell — if it runs and shows the RTX 3080,
   you're very likely fine.
3. WSL2's own kernel up to date: `wsl --update` from an elevated
   PowerShell.

Verify before the first real bring-up, not after:

```sh
docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi
```

That should print your RTX 3080 from inside a container. If it fails (e.g.
`could not select device driver with capabilities: [[gpu]]`), it's almost
always #2 or #3 above, not a missing setting.

## First-time setup

```sh
cd stacks/roastery
chmod +x *.sh
./setup-secrets.sh
```

`TZ` already defaults to `Asia/Kolkata`; change it in `.env.local` if
that's wrong for you. Nothing else needs filling in — immich-ml has no
secrets and no config template.

## Windows Firewall (the actual access control)

immich-ml "has no security measures whatsoever" (Immich's own
remote-machine-learning docs) — no auth, no API key. Restricting who can
reach it can't happen in the Linux side of WSL2: Docker Desktop's real
engine runs in its own hidden VM outside the WSL2 distro entirely, so a
`ufw` rule in there does nothing to a port Docker Desktop publishes. The
actual control point is Windows Defender Firewall, since Docker Desktop's
port publishing does traverse the real Windows network stack. From an
elevated PowerShell, scoped to percolator's LAN IP only:

```powershell
New-NetFirewallRule -DisplayName "immich-ml (percolator only)" `
  -Direction Inbound -Protocol TCP -LocalPort 3003 `
  -RemoteAddress 192.168.0.11 -Action Allow
```

**Check for a pre-existing broad rule first.** Windows Firewall allows a
packet if *any* matching rule permits it — a pre-existing broad
Docker/vpnkit allow rule can silently defeat this narrow one, making the
scoping above a no-op without you knowing:

```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*docker*" -or $_.DisplayName -like "*vpnkit*" } | Get-NetFirewallPortFilter
```

If a broad rule already allows 3003 (or all ports) from anywhere, either
narrow or remove it, or this new rule changes nothing.

## Bring up

```sh
./compose.sh immich-ml up -d
./compose.sh immich-ml logs -f
```

No web UI — this is a backend inference service only, nothing to log into.
Confirm it's alive from another machine on the LAN:

```sh
curl http://<roastery's LAN IP>:3003/ping
```

That should succeed from percolator and fail (connection refused/timeout)
from anywhere the firewall rule doesn't cover — the second half is as
important to check as the first.

Then, on percolator: put roastery's real LAN IP into
`stacks/percolator/.env.local`'s `IMMICH_ML_URL`
(`http://<roastery LAN IP>:3003`), and in Immich's own Admin UI
(*Administration → Settings → Machine Learning*), confirm the URL field
shows the same address — the maintainers call the env var deprecated, so
the UI is the forward-looking way to confirm or change it. Run
*Jobs → Smart Search / Face Detection* once it's connected.

## Is it working?

- [ ] `curl http://<roastery LAN IP>:3003/ping` succeeds from percolator.
- [ ] The same `curl` fails from a machine the firewall rule doesn't cover.
- [ ] Immich's Admin UI → Machine Learning Settings shows the URL connected,
      not an error.
- [ ] *Administration → Jobs* shows Smart Search / Face Detection actually
      progressing, not stuck at 0%.
- [ ] `docker logs immich-machine-learning` shows it picked up the GPU, not
      a silent CPU fallback (this looks identical to "it's working" until
      you notice inference is much slower than it should be).

## Gotchas

- **Server and ML versions must match exactly.** Bump
  `stacks/percolator/immich/docker-compose.yml`'s `immich-server` tag and
  this directory's `immich-machine-learning` tag together, never one alone.
- **Job concurrency has no compose/env knob.** Set it in Immich's own Admin
  UI (*Job Settings*) once connected — nothing here pre-configures it, and
  the default may be more concurrent inference than a shared gaming GPU
  should take on.
- **roastery asleep = no new smart-search indexing or face detection**,
  nothing else on the fleet breaks. Jobs resume once it's awake and the
  firewall/route is reachable again.
- **This container has zero authentication.** The Windows Firewall rule
  above is the entire protection — don't rely on the port mapping, a
  reverse proxy, or "it's not on a public IP" alone.
- **Read Immich's release notes before every version bump** — occasionally
  needs a manual migration step, same caution as percolator's own Immich.
