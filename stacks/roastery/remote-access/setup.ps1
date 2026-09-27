# setup.ps1: roastery on the tailnet, and Remote Desktop reachable over it
# (runbook, 2026-09-27; tailscale/README.md). Run from an elevated PowerShell
# (Run as administrator); safe to run again.
#
#   .\setup.ps1              tailnet only: RDP from Tailscale addresses
#   .\setup.ps1 -AllowLan    also from the house LAN (LAN_CIDR in stacks/fleet.env)
#
# What it does:
#
#   1. Tailscale, from the MSI pinned below and checked against its SHA-256
#      (the same rule as ufw-docker on the nodes). Tailscale updates itself
#      after that (step 2), so the pin only matters for a first install.
#   2. Joins the tailnet as `roastery`, unattended, so it stays connected with
#      nobody signed in, which is exactly when you'd want to RDP in. roastery
#      is joined as you, not tagged: it's your PC, and the policy's
#      autogroup:self rule is what lets your laptop in.
#   3. Remote Desktop on, with Network Level Authentication (the password is
#      checked before a session, and a login screen, is ever set up).
#   4. Windows Firewall: 3389 (TCP and UDP) from 100.64.0.0/10 only, plus the
#      LAN with -AllowLan. Windows' own "Remote Desktop" rules, which allow
#      everyone, are turned off. Windows lets a packet in if *any* rule does,
#      so anything else still open on 3389 is listed at the end.
#
param(
    [string]$TailscaleVersion = '1.102.4',
    [string]$MsiSha256 = '80eb007e39dfebe17299fa1a09c79a8e1d934f76e0246c0817ebe3af675b7ef6',
    [string]$Hostname = 'roastery',
    [switch]$AllowLan
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\_lib\purrbrews.ps1')

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell (Run as administrator).'
}
$edition = (Get-CimInstance Win32_OperatingSystem).Caption
if ($edition -match 'Home') { throw "$edition can't host Remote Desktop; it needs Pro or better." }

$Tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$Tailnet = '100.64.0.0/10'

# -- 1. Tailscale ---------------------------------------------------------------
Write-Step 'Tailscale'
if (-not (Test-Path -LiteralPath $Tailscale)) {
    $msi = Join-Path $env:TEMP "tailscale-setup-$TailscaleVersion-amd64.msi"
    $url = "https://pkgs.tailscale.com/stable/tailscale-setup-$TailscaleVersion-amd64.msi"
    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
    $hash = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $MsiSha256) {
        Remove-Item -LiteralPath $msi -Force
        throw "Tailscale $TailscaleVersion MSI checksum mismatch ($hash); not installing."
    }
    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/quiet', '/norestart' -Wait -PassThru
    Remove-Item -LiteralPath $msi -Force
    if ($p.ExitCode -notin 0, 3010) { throw "The Tailscale installer exited with $($p.ExitCode)." }
    Write-Host "  installed Tailscale $TailscaleVersion (checksum verified)"
} else {
    Write-Host "  already installed: $((& $Tailscale version) | Select-Object -First 1)"
}

# -- 2. join --------------------------------------------------------------------
Write-Step "Joining the tailnet as '$Hostname'"
$state = ''
try { $state = ((& $Tailscale status --json) | ConvertFrom-Json).BackendState } catch { }
if ($state -ne 'Running') {
    Write-Host '  Open the link Tailscale prints and sign in with your own account.'
}
# --reset: this line is the whole configuration, so a setting clicked in the
# tray can't quietly outlive it. --unattended: keep running with nobody signed in.
& $Tailscale up --reset --unattended "--hostname=$Hostname"
if ($LASTEXITCODE -ne 0) { throw 'tailscale up failed (see above).' }
& $Tailscale set --auto-update=true
if ($LASTEXITCODE -ne 0) { Write-Warning "Couldn't turn on Tailscale's auto-update; update it from the tray instead." }
$ip = (& $Tailscale ip -4) | Select-Object -First 1
Write-Host "  $Hostname is $ip on the tailnet"

# -- 3. Remote Desktop ----------------------------------------------------------
Write-Step 'Remote Desktop'
$ts = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty -Path $ts -Name fDenyTSConnections -Value 0
Set-ItemProperty -Path "$ts\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1
Write-Host '  on, Network Level Authentication required'

# -- 4. firewall ----------------------------------------------------------------
Write-Step 'Windows Firewall'
# The built-in group, by its resource name so a non-English Windows matches too.
Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
$from = @($Tailnet)
if ($AllowLan) {
    $fleet = Read-EnvFile (Join-Path $script:Stacks 'fleet.env')
    if (-not $fleet['LAN_CIDR']) { throw 'No LAN_CIDR in stacks/fleet.env.' }
    $from += $fleet['LAN_CIDR']
}
foreach ($proto in 'TCP', 'UDP') {
    $name = "purrbrews-rdp-$($proto.ToLower())"
    Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -Name $name -DisplayName "purrbrews Remote Desktop ($proto, tailnet$(if ($AllowLan) { ' + LAN' }))" `
        -Direction Inbound -Protocol $proto -LocalPort 3389 -RemoteAddress $from -Profile Any -Action Allow | Out-Null
}
Write-Host "  3389/tcp+udp from $($from -join ', ') only; Windows' own Remote Desktop rules are off"

$open = @()
foreach ($filter in Get-NetFirewallPortFilter -All -ErrorAction SilentlyContinue) {
    if (@($filter.LocalPort) -notcontains '3389') { continue }
    $rule = Get-NetFirewallRule -Name $filter.InstanceID -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled -eq 'True' -and $rule.Direction -eq 'Inbound' -and $rule.Action -eq 'Allow' `
        -and $rule.Name -notlike 'purrbrews-rdp-*') {
        $open += "$($rule.DisplayName) [$($rule.Name)]"
    }
}
if ($open.Count -gt 0) {
    Write-Warning "Other rules still let 3389 in, so the scoping above isn't the whole story:"
    $open | ForEach-Object { Write-Warning "  $_" }
}

# -- done -----------------------------------------------------------------------
Write-Step 'Done'
Write-Host "From a laptop or phone on the tailnet:  mstsc /v:$Hostname"
Write-Host ''
Write-Host 'Still to do by hand (tailscale/README.md):'
Write-Host "  - Admin console -> Machines -> $Hostname -> Disable key expiry, or it drops off in 180 days."
Write-Host '  - Sign in over RDP with your account *password*; a PIN or Windows Hello does not work there.'
Write-Host '  - It must be awake: ssh barista@cellar, then /opt/purrbrews/stacks/cellar/restic/wake-roastery.sh'
