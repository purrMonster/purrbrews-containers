# install.ps1: Scrutiny's native Windows collector on roastery, as a scheduled
# task every six hours, sending SMART data to the hub on cellar like the Linux
# nodes' collectors. Docker Desktop can't pass raw Windows disks to a container,
# so this one is the release .exe plus smartmontools, no Docker.
#
# From an elevated Windows PowerShell 5.1 (Run as administrator), from the
# deploy checkout:
#   powershell -ExecutionPolicy Bypass -File .\stacks\roastery\scrutiny-collector\install.ps1
#       install, or update after a pull, and run it once
#   ... -ExePath <file>   use an already downloaded collector .exe (still checked
#                         against the pinned SHA-256; for when GitHub hangs)
#   ... -Uninstall        remove the task and its runtime folder
#
# The task runs as SYSTEM (smartctl needs admin to read the disks), so what it
# runs lives in a protected copy, C:\Program Files\purrbrews-scrutiny, writable
# only by SYSTEM and Administrators: the same rule as Traefik's runtime
# (init\lib\windows-runtime.ps1). Nothing the task executes comes from the
# checkout, the user's TEMP or a folder a normal user can write to.
#
# The collector's version must match the hub's image on cellar; the tests
# check it. Dependabot can't bump this file: after a Scrutiny bump in compose,
# update $CollectorVersion and $CollectorSha256 here from the release page
# (each asset lists its sha256), then run this again.
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$ExePath = ''
)
$ErrorActionPreference = 'Stop'

$TaskName = 'purrbrews-scrutiny-collector'
$CollectorVersion = 'v0.9.5'
$CollectorSha256 = '2d6c3db4a0474f2ea685efe845ab5a477aa89c08b6cb0f9de20bbdcceadf4172'
$CollectorUrl = "https://github.com/AnalogJ/scrutiny/releases/download/$CollectorVersion/scrutiny-collector-metrics-windows-amd64.exe"
# winget checks the installer's own hash from its manifest.
$SmartmontoolsVersion = '7.5'
$HostId = 'roastery'

$Runtime = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'purrbrews-scrutiny'
$Exe = Join-Path $Runtime 'scrutiny-collector-metrics.exe'
$Config = Join-Path $Runtime 'collector.yaml'
$Log = Join-Path $Runtime 'collector.log'

function Find-Smartctl {
    # The installer records where it went; 64-bit Windows gets the 64-bit
    # binaries under Program Files, but trust the record over the guess.
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\smartmontools',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\smartmontools')
    $dirs = @($keys | ForEach-Object { (Get-ItemProperty -LiteralPath $_ -ErrorAction SilentlyContinue).InstallLocation } |
              Where-Object { $_ })
    $dirs += (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'smartmontools')
    foreach ($dir in $dirs) {
        $exe = Join-Path $dir 'bin\smartctl.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell (Run as administrator).'
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($Uninstall) {
    if ($existing) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed the task $TaskName."
    } else { Write-Host "No task named $TaskName." }
    if (Test-Path -LiteralPath $Runtime) { Remove-Item -LiteralPath $Runtime -Recurse -Force; Write-Host "Removed $Runtime." }
    Write-Host 'smartmontools stays installed: winget uninstall --id smartmontools.smartmontools --exact'
    Write-Host "roastery's drives stay in Scrutiny's history; delete them in its UI if you want them gone."
    exit 0
}

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Use Windows PowerShell 5.1 (powershell.exe): the protected runtime needs .NET Framework ACL support.'
}
. (Join-Path $PSScriptRoot '..\..\_lib\purrbrews.ps1')
. (Join-Path $script:Root 'init\lib\windows-runtime.ps1')
$ErrorActionPreference = 'Stop'

$fleet = Read-EnvFile (Join-Path $script:Stacks 'fleet.env')
$cellar = $fleet['CELLAR_LAN_IP']
if (-not $cellar) { throw 'stacks/fleet.env has no CELLAR_LAN_IP.' }

# -- smartmontools ---------------------------------------------------------------
$Smartctl = Find-Smartctl
if (-not $Smartctl) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget is missing; install smartmontools $SmartmontoolsVersion by hand" }
    Write-Host "Installing smartmontools $SmartmontoolsVersion ..."
    & winget install --id smartmontools.smartmontools --exact --version $SmartmontoolsVersion --silent `
        --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install smartmontools exited with $LASTEXITCODE" }
    $Smartctl = Find-Smartctl
    if (-not $Smartctl) { throw "smartmontools installed, but no bin\smartctl.exe where its uninstall record points" }
}
# SYSTEM runs it: nobody but administrators may be able to change it or its folders.
Assert-AdminOnlyPath $Smartctl -Ancestor
Write-Host "smartctl: $Smartctl ($(& $Smartctl --version | Select-Object -First 1))"

# -- protected runtime -----------------------------------------------------------
Assert-AdminOnlyPath (Split-Path -Parent $Runtime) -Ancestor
if (-not (Test-Path -LiteralPath $Runtime)) {
    [IO.Directory]::CreateDirectory($Runtime, (New-AdminOnlyDirectoryAcl)) | Out-Null
}
Assert-AdminOnlyPath $Runtime
foreach ($item in Get-ChildItem -LiteralPath $Runtime -Force -Recurse) { Assert-AdminOnlyPath $item.FullName }

if ($existing) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }

# The collector .exe: copied into the runtime first, then hashed there, so the
# bytes that were checked are the bytes SYSTEM runs.
$download = $null
try {
    if ($ExePath) {
        $source = (Resolve-Path -LiteralPath $ExePath).Path
    } else {
        $download = Join-Path $env:TEMP "scrutiny-collector-$([guid]::NewGuid().ToString('N')).exe"
        Write-Host "Downloading $CollectorUrl ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $CollectorUrl -OutFile $download -UseBasicParsing -TimeoutSec 300
        $source = $download
    }
    $staged = "$Exe.new"
    Copy-AdminOnlyFile $source $staged
    $hash = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $CollectorSha256) {
        Remove-Item -LiteralPath $staged -Force
        throw "Collector checksum mismatch: got $hash, expected $CollectorSha256 ($CollectorVersion). Nothing installed."
    }
    Move-Item -LiteralPath $staged -Destination $Exe -Force
    Write-Host "collector: $CollectorVersion, sha256 $hash"
} finally {
    if ($download -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download -Force }
}

# collector.yaml: written here, not kept in the repo, because it holds this
# PC's paths. Single-quoted YAML takes the backslashes literally. The
# endpoint keeps its trailing slash: the collector adds one only when the
# endpoint comes from a flag or an environment variable, not from this file.
# The log is rewritten from the top each run, not truncated: read its first
# lines, or the timestamps.
$yaml = @(
    '# Written by stacks\roastery\scrutiny-collector\install.ps1; run it again instead of editing.',
    'version: 1',
    'host:',
    "  id: '$HostId'",
    'api:',
    "  endpoint: 'http://${cellar}:8080/'",
    'log:',
    "  file: '$Log'",
    'commands:',
    "  metrics_smartctl_bin: '$Smartctl'"
)
$tmp = Join-Path $env:TEMP "scrutiny-collector-$([guid]::NewGuid().ToString('N')).yaml"
try {
    [IO.File]::WriteAllText($tmp, (($yaml -join "`n") + "`n"))
    Copy-AdminOnlyFile $tmp $Config
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
foreach ($item in Get-ChildItem -LiteralPath $Runtime -Force -Recurse) { Assert-AdminOnlyPath $item.FullName }

# -- the task --------------------------------------------------------------------
# Every six hours from 05:35, a few minutes after the Linux collectors
# (00:00 UTC = 05:30 IST and every six hours). StartWhenAvailable catches up a
# run missed while the PC was off. 30 minutes is plenty: a run takes seconds.
$action = New-ScheduledTaskAction -Execute $Exe -WorkingDirectory $Runtime -Argument "run --config `"$Config`""
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).Date.AddHours(5).AddMinutes(35)) -RepetitionInterval (New-TimeSpan -Hours 6)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $taskPrincipal `
    -Settings $settings -Force `
    -Description "purrBrews: Scrutiny collector $CollectorVersion, SMART data to cellar every 6 h (stacks\roastery\scrutiny-collector)." | Out-Null

# -- run it once -------------------------------------------------------------------
Start-ScheduledTask -TaskName $TaskName
$deadline = (Get-Date).AddMinutes(3)
do { Start-Sleep -Seconds 3 } while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host ''
Write-Host "Task:        $TaskName, as SYSTEM, every 6 h; next run $($info.NextRunTime)"
Write-Host "Last result: $($info.LastTaskResult) (0 = success)"
if (Test-Path -LiteralPath $Log) {
    Write-Host "Log (last lines of $Log):"
    Get-Content -LiteralPath $Log -Tail 8 | ForEach-Object { Write-Host "  $_" }
}
Write-Host ''
Write-Host "Check: http://${cellar}:8080 lists roastery's drives under '$HostId'."
if ($info.LastTaskResult -ne 0) { exit 1 }
