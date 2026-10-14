# Scrutiny collector (roastery)

roastery's drives in Scrutiny on cellar, next to the Linux nodes'. Docker
Desktop can't pass raw Windows disks to a container, so roastery doesn't run the
collector image: it runs Scrutiny's own Windows build of the collector, with
smartmontools for `smartctl`, from a scheduled task.

| | |
|---|---|
| What runs | `scrutiny-collector-metrics-windows-amd64.exe`, the same version as the hub's image on cellar (the tests check it) |
| Where | `C:\Program Files\purrbrews-scrutiny`, writable only by SYSTEM and Administrators |
| As | SYSTEM: `smartctl` needs admin rights to read the disks |
| When | every 6 hours from 05:35, a few minutes after the Linux collectors; a missed run catches up when the PC is back on |
| Sends to | `http://${CELLAR_LAN_IP}:8080`, host `roastery` in the dashboard |
| Log | `C:\Program Files\purrbrews-scrutiny\collector.log` (admin to read) |

## Install, update, remove

From an elevated Windows PowerShell 5.1, in the deploy checkout:

```powershell
cd C:\purrbrews-deploy
powershell -ExecutionPolicy Bypass -File .\stacks\roastery\scrutiny-collector\install.ps1
```

It installs smartmontools with winget if it's missing (pinned version; winget
checks the installer's hash), downloads the collector, checks it against the
SHA-256 pinned in the script, copies it into the protected folder, writes
`collector.yaml` there, registers the task and runs it once. Run it again after
a pull that changes it; it replaces what's there.

- GitHub downloads hang now and then from this ISP (runbook Backlog). Download
  the `.exe` in a browser and pass `-ExePath <file>`: it's checked against the
  same pinned hash.
- `-Uninstall` removes the task and the folder. smartmontools stays
  (`winget uninstall --id smartmontools.smartmontools --exact`), and so do
  roastery's drives in Scrutiny's history (delete them in its UI).

## Why it's built this way

- **A protected copy, not the checkout.** A task running as SYSTEM must not
  run anything a normal user can replace. The checkout, `%TEMP%` and
  `C:\ProgramData` are all writable by someone else, so the script copies the
  bytes into a folder with an admin-only ACL and hashes the copy there: what
  was checked is what runs. The same rule as Traefik's runtime
  (`init\lib\windows-runtime.ps1`, whose helpers it uses). `smartctl.exe` is
  checked too: nobody but administrators may be able to change it or its
  folders.
- **`collector.yaml` is written, not committed.** It holds this PC's paths.
  Its endpoint ends in `/`: the collector adds the slash itself only for an
  endpoint given as a flag or environment variable.
- **Updating.** Dependabot bumps the hub and the Linux collectors in compose,
  not this script. After such a bump the version test fails until
  `$CollectorVersion` and `$CollectorSha256` here match: take the hash from
  the release page (every asset lists its `sha256`), then run the script again.

## Check it

```powershell
Get-ScheduledTaskInfo purrbrews-scrutiny-collector    # LastTaskResult 0
Start-ScheduledTask purrbrews-scrutiny-collector      # a run now, instead of waiting
```

Then Scrutiny (`http://${CELLAR_LAN_IP}:8080` or `scrutiny.${DOMAIN}`) lists
roastery's NVMe and its old Seagate under `roastery`. The Seagate is the same
model as cellar's flagged ST1000, so expect the same misread attribute 188.
