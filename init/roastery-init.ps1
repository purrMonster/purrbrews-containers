# roastery-init.ps1: take a freshly installed Windows 11 roastery back to
# "everything the fleet expects of it", in one run. The Windows twin of
# purrbrews-init.sh: roastery isn't a fleet node, but it holds the restic
# repository, takes RDP over the tailnet, lends its GPU and serves the
# bootstrap container, and after the 2026-10-07 wipe none of that came back by
# itself. It follows stacks/roastery/README.md, "Rebuilding roastery", step by
# step, and does the parts that used to be clicks or hand-made tasks.
#
# Run from an elevated PowerShell (Run as administrator), from the repo:
#
#   powershell -ExecutionPolicy Bypass -File .\init\roastery-init.ps1
#
#   -ListSteps                 print the step names and exit
#   -Only a,b / -Skip a,b      run only / all but these steps
#   -Yes                       don't ask before the rename, the joins, the task
#   -AllowLan                  RDP from the LAN too (remote-access\setup.ps1)
#   -AllowEmptyRepository      open the backup target with no repository in it
#                              (a brand-new repository; see backup_target)
#   -WakeAdapter <name>        the NIC that wakes on LAN (default: the one with
#                              the default route)
#   -SkipModels                don't run llama-swap's fetch-models (~17 GB)
#
# Steps, in order:
#   hostname       the PC is called roastery (Rename-Computer; restart after)
#   network        the wired adapter is Private, and has ROASTERY_LAN_IP
#   power          never sleeps or hibernates on AC (runbook, 2026-09-29)
#   prereqs        Git, Docker Desktop (winget), WSL2, NVIDIA driver >= 545
#   ssh_key        this user's ~\.ssh\id_ed25519
#   bootstrap      purrbrews-bootstrap: data\, the container, 8443 from the LAN
#   remote_access  Tailscale + RDP (stacks\roastery\remote-access\setup.ps1)
#   backup_target  the SFTP target (stacks\roastery\backup-target\setup.ps1),
#                  refused while C:\purrbrews\restic holds no repository: the
#                  repository comes back from Drive first (RECOVERY.md part B)
#   apps           .env.local + render, the GPU check, immich-ml (+ its firewall
#                  rule), Komodo Periphery, llama-swap (fetch-models, up)
#   traefik        firewall for traefik.exe, the leftover ollama.yml removed, and
#                  the `traefik` scheduled task (at boot, as SYSTEM, no time limit)
#   game_mode      stacks\roastery\game-mode\install.ps1
#   bootstrap      purrbrews-bootstrap, only when you say so: data\, the
#                  container, 8443 from the LAN. Needed only to (re)build a node
#
# Safe to run again: every step looks before it changes anything. A step that
# can't finish yet says what it needs and the run carries on; the summary at
# the end lists those, the warnings and the follow-ups on the nodes. The whole
# run is logged to C:\ProgramData\purrbrews\logs\roastery-init-*.log.
#
# What it deliberately does NOT do: download traefik.exe (pick and verify the
# release yourself, traefik\README.md), restore the repository (that's
# RECOVERY.md part B, with secrets from the vault), bring up meowGram or
# persianPerch's kitten (their own repos), or change anything on a node. The
# node-side follow-ups are printed instead.
[CmdletBinding()]
param(
    [string[]]$Only = @(),
    [string[]]$Skip = @(),
    [switch]$ListSteps,
    [switch]$Yes,
    [switch]$AllowLan,
    [switch]$AllowEmptyRepository,
    [string]$WakeAdapter = '',
    [switch]$SkipModels
)

# The order of roastery's README, "Rebuilding roastery".
$AllSteps = @('hostname', 'network', 'power', 'prereqs', 'ssh_key', 'remote_access',
              'backup_target', 'apps', 'traefik', 'game_mode', 'bootstrap')
if ($ListSteps) { $AllSteps; return }

. (Join-Path $PSScriptRoot '..\stacks\_lib\purrbrews.ps1')
$ErrorActionPreference = 'Stop'

$Hostname = 'roastery'
$Roastery = Join-Path $script:Stacks 'roastery'
$BackupRoot = 'C:\purrbrews'
$LogDir = Join-Path $env:ProgramData 'purrbrews\logs'

# -- output and bookkeeping ----------------------------------------------------
$script:Current = 'startup'
$script:Warnings = @()
$script:Blocked = @()
$script:Failed = @()
$script:Todo = @()
$script:NeedsRestart = $false

function Ok([string]$m)   { Write-Host "  ok $m" -ForegroundColor Green }
function Note([string]$m) { Write-Host "  $m" }
function Warn([string]$m) { Write-Warning $m; $script:Warnings += "[$($script:Current)] $m" }
function Todo([string]$m) { $script:Todo += "[$($script:Current)] $m" }
# A step that can't finish yet: say what it needs, and let the run carry on.
function Block([string]$m) {
    Write-Host "  BLOCKED: $m" -ForegroundColor Yellow
    $script:Blocked += "[$($script:Current)] $m"
}

function Confirm-Change([string]$Question) {
    if ($Yes) { return $true }
    if ([Console]::IsInputRedirected) { Warn "No console to confirm '$Question'; pass -Yes to allow."; return $false }
    return ((Read-Host "  $Question [y/N]") -match '^(y|yes)$')
}

function Update-Path {
    # winget installs don't reach this session's PATH on their own.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    & docker info *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-LanAdapter {
    # The adapter with the default route: the one the fleet knows this PC by.
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    if (-not $route) { return $null }
    $adapter = Get-NetAdapter -InterfaceIndex $route.ifIndex
    $ip = Get-NetIPAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    [pscustomobject]@{
        Index   = $route.ifIndex
        Name    = $adapter.Name
        Desc    = $adapter.InterfaceDescription
        Mac     = ($adapter.MacAddress -replace '-', ':').ToLower()
        Media   = $adapter.PhysicalMediaType
        IP      = if ($ip) { $ip.IPAddress } else { '' }
    }
}

function Set-FirewallRule([string]$Name, [string]$Display, [hashtable]$Spec) {
    # Ours by Name: removed and made again, so a re-run is the whole truth.
    Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name $Name -DisplayName $Display -Direction Inbound -Action Allow @Spec | Out-Null
}

$Fleet = Read-EnvFile (Join-Path $script:Stacks 'fleet.env')
foreach ($key in 'ROASTERY_LAN_IP', 'LAN_CIDR', 'PERCOLATOR_LAN_IP') {
    if (-not $Fleet[$key]) { throw "stacks/fleet.env has no $key." }
}
$NodeIPs = [ordered]@{}
foreach ($key in $Fleet.Keys) {
    if ($key -match '^([A-Z]+)_LAN_IP$' -and $key -ne 'ROASTERY_LAN_IP') { $NodeIPs[$Matches[1].ToLower()] = $Fleet[$key] }
}

# =============================================================================
# Steps
# =============================================================================

function Step-hostname {
    if ($env:COMPUTERNAME -ieq $Hostname) { Ok "this PC is $Hostname"; return }
    if (Confirm-Change "Rename this PC from $($env:COMPUTERNAME) to $Hostname (takes effect after a restart)?") {
        Rename-Computer -NewName $Hostname -Force
        $script:NeedsRestart = $true
        Ok "renamed to $Hostname; restart before the remote_access step means anything to Tailscale"
    } else {
        Warn "still $($env:COMPUTERNAME); Tailscale gets --hostname=$Hostname either way, but the LAN name differs"
    }
}

function Step-network {
    $lan = Get-LanAdapter
    if (-not $lan) { Block 'no default route: is the cable in?'; return }
    Note "'$($lan.Name)' ($($lan.Desc)), MAC $($lan.Mac), IPv4 $($lan.IP)"
    if ($lan.Media -match '802\.11|Wireless') { Warn "the default route is on Wi-Fi ($($lan.Name)); the fleet is wired-only and wake-on-LAN needs the cable" }

    $conn = Get-NetConnectionProfile -InterfaceIndex $lan.Index -ErrorAction SilentlyContinue
    if ($conn -and $conn.NetworkCategory -eq 'Public') {
        # The bootstrap rule is Private-only, and Public is what a fresh install picks.
        Set-NetConnectionProfile -InterfaceIndex $lan.Index -NetworkCategory Private
        Ok "network profile Public -> Private"
    } elseif ($conn) {
        Ok "network profile $($conn.NetworkCategory)"
    }

    $want = $Fleet['ROASTERY_LAN_IP']
    if ($lan.IP -eq $want) {
        Ok "address $want, as stacks/fleet.env says"
    } else {
        Warn ("this PC is $($lan.IP), but stacks/fleet.env says ${want}: every node's BACKUP_REPOSITORY and the bootstrap URL point there. " +
              "Give $($lan.Mac) a static lease for $want in Pi-hole on sieve (Settings -> DHCP -> Static DHCP), then: ipconfig /release; ipconfig /renew")
    }
}

function Step-power {
    # roastery stays awake until wake-on-demand is designed (runbook backlog,
    # 2026-09-29). Hibernation off also keeps Fast Startup from ever running.
    foreach ($setting in 'standby-timeout-ac', 'hibernate-timeout-ac') {
        & powercfg /change $setting 0
        if ($LASTEXITCODE -ne 0) { throw "powercfg /change $setting failed" }
    }
    & powercfg /hibernate off
    if ($LASTEXITCODE -ne 0) { throw 'powercfg /hibernate off failed' }
    Ok 'never sleeps or hibernates on AC; hibernation off (the screen still turns off as you like)'
}

function Step-prereqs {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Block "winget is missing: install 'App Installer' from the Microsoft Store, then run this step again"
        return
    }
    $packages = @(
        @{ Id = 'Git.Git';              Present = { [bool](Get-Command git -ErrorAction SilentlyContinue) } },
        @{ Id = 'Docker.DockerDesktop'; Present = { Test-Path (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe') } }
    )
    foreach ($p in $packages) {
        if (& $p.Present) { Ok "$($p.Id) installed"; continue }
        Note "installing $($p.Id) ..."
        & winget install --id $p.Id --exact --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "winget install $($p.Id) exited with $LASTEXITCODE" }
        Update-Path
        Ok "$($p.Id) installed"
        if ($p.Id -eq 'Docker.DockerDesktop') { $script:NeedsRestart = $true }
    }

    # WSL2: Docker Desktop's backend, and the GPU path for immich-ml.
    & wsl.exe --status *> $null
    if ($LASTEXITCODE -ne 0) {
        & wsl.exe --install --no-distribution
        $script:NeedsRestart = $true
        Ok 'WSL installed (restart needed)'
    } else {
        & wsl.exe --update *> $null
        Ok 'WSL present and updated'
    }

    # The NVIDIA driver is the gaming driver too, so it's yours to install;
    # this only checks it's new enough for CUDA 12.3 in containers.
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) {
        Warn 'no nvidia-smi: install the NVIDIA driver (>= 545) before immich-ml'
    } else {
        $line = (& nvidia-smi --query-gpu=name,driver_version --format=csv,noheader) | Select-Object -First 1
        $name, $version = ($line -split ',') | ForEach-Object { $_.Trim() }
        if ([version]$version -ge [version]'545.0') { Ok "$name, driver $version" }
        else { Warn "$name has driver $version; immich-ml needs >= 545 (CUDA 12.3)" }
    }

    if (Test-Docker) { Ok 'Docker engine answers' }
    else { Warn 'Docker engine not answering yet: start Docker Desktop once (accept its terms, WSL2 backend), then run the apps step' }
    Note "Docker Desktop -> Settings -> General: tick 'Start Docker Desktop when you sign in' (immich-ml, llama-swap and meowGram live in it)"

}

function Step-ssh_key {
    $key = Join-Path $HOME '.ssh\id_ed25519'
    $keygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
    if (-not (Test-Path -LiteralPath $keygen)) { Block 'the OpenSSH client is missing (Settings -> System -> Optional features)'; return }
    if (Test-Path -LiteralPath $key) {
        Ok "key exists: $((& $keygen -lf "$key.pub") -join ' ')"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $key) | Out-Null
    Note 'making a new ed25519 key; pick a passphrase (or none) when asked'
    & $keygen -t ed25519 -C "$($env:USERNAME)@$Hostname" -f $key
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
    Ok "made $key"
    Todo ("This PC's SSH key is new, so no node trusts it yet; the old roastery key must not come back (the wipe was malware). " +
          "It reaches the nodes through bootstrap\data\authorized_keys once they've re-pinned the bootstrap server (bootstrap step).")
}

function Step-bootstrap {
    # Last and opt-in, as in the README: only a node being (re)built needs it.
    # While it's down the nodes' hourly key sync exits 75 (unreachable,
    # nothing changed); once it's up with a new TLS key, the sync fails loudly
    # on every node until each one re-pins.
    if (-not (Confirm-Change 'Bring up purrbrews-bootstrap (only needed to build or rebuild a node)?')) {
        Note 'left down; run -Only bootstrap when a node needs it'
        return
    }
    $dir = Join-Path $script:Root 'bootstrap'
    $data = Join-Path $dir 'data'
    New-Item -ItemType Directory -Force -Path $data | Out-Null

    $settings = Join-Path $data 'purrbrews-init.env'
    if (-not (Test-Path -LiteralPath $settings)) {
        Copy-Item -LiteralPath (Join-Path $script:Root 'init\purrbrews-init.env.example') -Destination $settings
        Ok 'data\purrbrews-init.env from the example (works as-is for the fleet)'
    } else {
        Ok 'data\purrbrews-init.env exists'
    }

    # authorized_keys is the fleet's whole SSH trust list: a key it doesn't
    # have is removed from every node within the hour. So it's never guessed.
    $keys = Join-Path $data 'authorized_keys'
    $pubFile = Join-Path $HOME '.ssh\id_ed25519.pub'
    $pub = if (Test-Path -LiteralPath $pubFile) { (Get-Content -LiteralPath $pubFile | Select-Object -First 1).Trim() } else { '' }
    if (-not (Test-Path -LiteralPath $keys)) {
        Block ("bootstrap\data\authorized_keys is missing, and it's the fleet's whole SSH trust list: whatever it leaves out, " +
               "every node removes within the hour once it trusts this server again. Rebuild it from what the nodes have now, from the Mac:`n" +
               "      ssh barista@sieve `"sed -n '/>>> purrbrews managed keys/,/<<< purrbrews managed keys/p' .ssh/authorized_keys | grep -v '^#'`" > authorized_keys`n" +
               "    copy that file here as bootstrap\data\authorized_keys, delete the old roastery key from it (the wipe was malware), add this PC's new key" +
               $(if ($pub) { ":`n      $pub" } else { ' (ssh_key step first)' }) +
               "`n    then: -Only bootstrap")
        return
    }
    $lines = @(Get-Content -LiteralPath $keys | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') })
    $bad = @($lines | Where-Object { $_ -notmatch '^(\S+ )?(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+|sk-\S+) [A-Za-z0-9+/=]+' })
    if ($bad.Count -gt 0) { Block "authorized_keys has $($bad.Count) line(s) that aren't public keys; fix them first"; return }
    if ($lines.Count -eq 0) { Block 'authorized_keys has no keys in it'; return }
    Ok "authorized_keys: $($lines.Count) key(s)"
    if ($pub -and -not ($lines | Where-Object { $_.Contains(($pub -split ' ')[1]) })) {
        Warn "this PC's own key isn't in authorized_keys, so roastery won't reach the nodes; add: $pub"
    }

    if (-not (Test-Docker)) { Block 'Docker engine not answering: start Docker Desktop, then -Only bootstrap'; return }

    # A new certs volume means a new TLS key, which every node has pinned.
    & docker volume inspect purrbrews-bootstrap_certs *> $null
    $freshKey = ($LASTEXITCODE -ne 0)
    Push-Location $dir
    try {
        & docker compose up -d --build
        if ($LASTEXITCODE -ne 0) { throw "docker compose up exited with $LASTEXITCODE" }
        Start-Sleep -Seconds 3
        $pin = ((& docker compose logs bootstrap) | Select-String -Pattern 'sha256//[A-Za-z0-9+/=]+' | Select-Object -Last 1).Matches.Value
    } finally { Pop-Location }
    Ok 'purrbrews-bootstrap is up'

    Set-FirewallRule 'purrbrews-bootstrap' 'purrbrews-bootstrap (8443 from the LAN)' @{
        Protocol = 'TCP'; LocalPort = 8443; RemoteAddress = $Fleet['LAN_CIDR']; Profile = 'Private'
    }
    Ok "8443/tcp from $($Fleet['LAN_CIDR']) (Private profile)"

    if ($pin) { Note "TLS pin: $pin" } else { Warn "couldn't read the TLS pin; docker compose logs bootstrap (in bootstrap\)" }
    if ($freshKey) {
        Todo ("The bootstrap server has a new TLS key (the old one went with the format), so every node's hourly key sync fails loudly and changes nothing. " +
              "On each node, after checking authorized_keys above is complete: set SSH_KEYS_PINNED_PUBKEY=$pin in /etc/purrbrews/purrbrews-init.env, " +
              "then sudo bash /opt/purrbrews/init/purrbrews-init.sh --only ssh_keys")
    }
}

function Step-remote_access {
    Note "If the old roastery is still in the Tailscale admin console (Machines), remove it first, or this PC joins as roastery-1."
    if (-not (Confirm-Change 'Run remote-access\setup.ps1 now (installs Tailscale, signs in, turns on RDP)?')) {
        Block 'skipped at the prompt'
        return
    }
    $script = Join-Path $Roastery 'remote-access\setup.ps1'
    if ($AllowLan) { & $script -AllowLan } else { & $script }
    Todo "Tailscale admin console -> Machines -> $Hostname -> Disable key expiry"
}

function Step-backup_target {
    $repo = Join-Path $BackupRoot 'restic'
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'config')) -and -not $AllowEmptyRepository) {
        # Repository first, nodes after (runbook 2026-10-07). drive-sync now
        # refuses an empty or re-initialised repository itself, but nightly
        # backups into an empty folder only fail, and a node authorized now
        # is one more thing to undo if the restore goes wrong.
        Block ("$repo has no restic repository, so no node is authorized yet. Restore it from Drive first: " +
               "stacks\roastery\flask\RECOVERY.md, part B, steps 2-5 (copy drive-crypt:repo down, check it, robocopy into $repo), " +
               "then -Only backup_target. A brand-new repository instead (the Drive copy then has to be moved aside by hand): -AllowEmptyRepository")
        return
    }

    $keys = Join-Path $Roastery 'backup-target\authorized_keys'
    if (-not (Test-Path -LiteralPath $keys)) {
        # Every node leaves its line in a world-readable file (backup.sh keys).
        Note 'no backup-target\authorized_keys; collecting each node''s line over SSH'
        $ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
        $got = @(); $missing = @()
        foreach ($node in $NodeIPs.Keys) {
            $out = & $ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new `
                "barista@$($NodeIPs[$node])" cat /etc/purrbrews/backup-authorize.txt 2>$null
            $line = @($out | Where-Object { $_ -match '^roastery from="' } | ForEach-Object { $_.Substring(9) }) | Select-Object -First 1
            if ($LASTEXITCODE -eq 0 -and $line) { $got += $line } else { $missing += $node }
        }
        if ($got.Count -eq 0) {
            Block ("couldn't collect any node's key (this PC's SSH key isn't trusted by the nodes yet?). From the Mac, for each node: " +
                   "ssh barista@<node> cat /etc/purrbrews/backup-authorize.txt, take the 'roastery ...' line without the leading 'roastery ', " +
                   "one per line in stacks\roastery\backup-target\authorized_keys, then -Only backup_target")
            return
        }
        Write-LFFile $keys (@('# One line per node, from /etc/purrbrews/backup-authorize.txt (collected by roastery-init.ps1)') + $got)
        Ok "collected $($got.Count) node key(s)"
        if ($missing.Count -gt 0) { Warn "no key from: $($missing -join ', '); add their lines, then backup-target\setup.ps1 -KeysOnly" }
    }

    $adapter = $WakeAdapter
    if (-not $adapter) { $lan = Get-LanAdapter; if ($lan) { $adapter = $lan.Name } }
    & (Join-Path $Roastery 'backup-target\setup.ps1') -WakeAdapter $adapter
    Todo ("roastery's SSH host key is new, and the nodes' backups refuse a changed key ('host key has CHANGED'). Compare the fingerprint printed above, then on each node: " +
          "sudo ssh-keygen -R $($Fleet['ROASTERY_LAN_IP']) -f /etc/purrbrews/backup_known_hosts && sudo ./backup.sh keys && sudo ./backup.sh doctor")
}

function Step-apps {
    & (Join-Path $Roastery 'setup-secrets.ps1')
    if ($LASTEXITCODE -ne 0) { Warn 'some templates did not render (setup-secrets.ps1 said which); fill .env.local and run render-configs.ps1' }

    if (-not (Test-Docker)) { Block 'Docker engine not answering: start Docker Desktop, then -Only apps'; return }
    $compose = Join-Path $Roastery 'compose.ps1'

    # immich-ml: the GPU first, then the firewall (its only protection), then up.
    Note 'checking the GPU inside Docker (pulls a small CUDA image the first time)'
    & docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi -L
    if ($LASTEXITCODE -ne 0) {
        Block 'no GPU inside Docker: NVIDIA driver >= 545, wsl --update, restart Docker Desktop; then -Only apps'
    } else {
        Ok 'GPU visible to containers'
        $percolator = $Fleet['PERCOLATOR_LAN_IP']
        Set-FirewallRule 'purrbrews-immich-ml' 'immich-ml (percolator only)' @{
            Protocol = 'TCP'; LocalPort = 3003; RemoteAddress = $percolator; Profile = 'Any'
        }
        Ok "3003/tcp from $percolator only"
        # Windows lets a packet in if *any* rule does.
        $broad = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*docker*' -or $_.DisplayName -like '*vpnkit*' -or $_.DisplayName -like '*com.docker*' })
        foreach ($r in $broad) { Warn "'$($r.DisplayName)' may let 3003 in from anywhere; check it (stacks\roastery\README.md, immich-ml)" }
        & $compose immich-ml up -d
        Ok 'immich-ml up; its tag must match immich-server on percolator'
        Todo "From percolator: curl http://$($Fleet['ROASTERY_LAN_IP']):3003/ping answers; from anywhere else it must not"
    }

    $corePub = Join-Path $Roastery 'komodo-periphery\keys\core.pub'
    if (Test-Path -LiteralPath $corePub) {
        & $compose komodo-periphery up -d
        Ok 'komodo-periphery up'
    } else {
        Block ("Komodo Periphery needs cellar's /srv/data/komodo/keys/core.pub at stacks\roastery\komodo-periphery\keys\core.pub " +
               "and an onboarding key in .env.local for the first connect; then -Only apps")
    }

    # llama-swap: the models into their volume (verified, resumable), then up.
    if ($SkipModels) {
        Note 'llama-swap: models skipped (-SkipModels); up -d starts it, and a model it lacks fails to load'
    } elseif (Confirm-Change 'Download llama-swap''s models now (~17 GB, checked against models.lock; safe to re-run)?') {
        & $compose llama-swap run --rm fetch-models
        Ok 'models fetched and verified'
    } else {
        Todo 'llama-swap models: .\compose.ps1 llama-swap run --rm fetch-models (in stacks\roastery)'
    }
    & $compose llama-swap up -d
    Ok 'llama-swap up on 127.0.0.1:9292'
    Todo 'llama-swap: curl.exe http://127.0.0.1:9292/health answers OK, and /v1/models lists assistant and fast (llama-swap\README.md, "Is it working?")'
    Todo 'meowGram and persianPerch''s kitten come from their own repos (stacks\roastery\meowgram\README.md; persianPerch integration/roastery)'
}

function Step-traefik {
    $dir = Join-Path $Roastery 'traefik'
    $exe = Join-Path $dir 'traefik.exe'
    $start = Join-Path $dir 'start.ps1'
    if (-not (Test-Path -LiteralPath $exe)) {
        Block "no traefik\traefik.exe: download the Windows amd64 Traefik v3 release, check its published checksum, put it at $exe; then -Only traefik"
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'secrets.env.local'))) {
        Block 'no traefik\secrets.env.local: copy secrets.env.example and paste CF_DNS_API_TOKEN (never type it); then -Only traefik'
        return
    }

    # Rendered before 2026-10-07 and gitignored: its middleware clashes with
    # the llama-swap route's (traefik\README.md).
    $leftover = Join-Path $dir 'config\dynamic\ollama.yml'
    if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Force; Ok 'removed the leftover config\dynamic\ollama.yml' }

    Set-FirewallRule 'purrbrews-traefik' 'purrbrews Traefik (80, 443 from the LAN)' @{
        Protocol = 'TCP'; LocalPort = @(80, 443); Program = $exe; RemoteAddress = $Fleet['LAN_CIDR']; Profile = 'Any'
    }
    Ok "80, 443/tcp to traefik.exe from $($Fleet['LAN_CIDR'])"

    # Hand-made until now, so it went with the wipe (runbook 2026-10-07 asks
    # for it in the repo). Windows' default 3-day limit killed Traefik on
    # 2026-10-03: PT0S here, so that can't come back.
    if (-not (Confirm-Change 'Register the traefik scheduled task (at boot, as SYSTEM) and start it?')) { Block 'skipped at the prompt'; return }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $dir `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$start`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName 'traefik' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Stop-ScheduledTask -TaskName 'traefik' -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName 'traefik'
    Start-Sleep -Seconds 5
    $limit = (Get-ScheduledTask -TaskName 'traefik').Settings.ExecutionTimeLimit
    $listening = @(Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue)
    if ($listening.Count -gt 0) { Ok "traefik task running (ExecutionTimeLimit $limit), listening on 443" }
    else { Warn "the traefik task started but nothing listens on 443 yet; Get-ScheduledTaskInfo traefik, and run start.ps1 by hand to see why" }
    Todo "roastery's IP is in percolator's FORWARD_AUTH_CLIENTS and in PIHOLE_DNS_EXTRA_HOSTS on sieve and mochaPot (traefik\README.md, steps 6-7); check they still match $($Fleet['ROASTERY_LAN_IP'])"
}

function Step-game_mode {
    & (Join-Path $Roastery 'game-mode\install.ps1')
    Todo 'game mode: .\game-mode\game-mode.ps1 -Once, then start a game and watch game-mode.log (game-mode\README.md)'
}

# =============================================================================
# Main
# =============================================================================

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell (Run as administrator).'
}
$edition = (Get-CimInstance Win32_OperatingSystem).Caption
if ($edition -match 'Home') { throw "$edition can't host Remote Desktop; roastery needs Pro or better." }

# -Only a,b from cmd/-File arrives as one string; split it either way.
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
foreach ($name in $Only + $Skip) {
    if ($AllSteps -notcontains $name) { throw "Unknown step '$name' (steps: $($AllSteps -join ', '))." }
}
$run = @($AllSteps | Where-Object { ($Only.Count -eq 0 -or $Only -contains $_) -and $Skip -notcontains $_ })

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$log = Join-Path $LogDir "roastery-init-$(Get-Date -Format yyyyMMdd-HHmmss).log"
try { Start-Transcript -LiteralPath $log | Out-Null } catch { $log = $null }

try {
    Write-Host "roastery-init: $($run -join ', ')"
    foreach ($step in $run) {
        $script:Current = $step
        Write-Step $step
        try {
            & "Step-$step"
        } catch {
            Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $script:Failed += "[$step] $($_.Exception.Message)"
        }
    }

    $script:Current = 'summary'
    Write-Step 'Summary'
    if ($script:Failed.Count)   { Write-Host 'Failed (fix and re-run with -Only <step>):' -ForegroundColor Red; $script:Failed | ForEach-Object { Write-Host "  $_" } }
    if ($script:Blocked.Count)  { Write-Host 'Waiting on something:' -ForegroundColor Yellow; $script:Blocked | ForEach-Object { Write-Host "  $_" } }
    if ($script:Warnings.Count) { Write-Host 'Warnings:' -ForegroundColor Yellow; $script:Warnings | ForEach-Object { Write-Host "  $_" } }
    if ($script:Todo.Count)     { Write-Host 'Follow-ups (mostly on the nodes, yours to run):'; $script:Todo | ForEach-Object { Write-Host "  - $_" } }
    if ($script:NeedsRestart)   { Write-Host 'Restart Windows, then run this again: finished steps are no-ops.' -ForegroundColor Cyan }
    if (-not ($script:Failed.Count + $script:Blocked.Count)) { Write-Host 'Every step finished.' -ForegroundColor Green }
    if ($log) { Write-Host "Log: $log" }
} finally {
    if ($log) { Stop-Transcript | Out-Null }
}
if ($script:Failed.Count + $script:Blocked.Count) { exit 1 }
