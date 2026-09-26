# setup.ps1: make roastery the fleet's backup target (runbook, 2026-09-27).
# Run from an elevated PowerShell (Run as administrator); safe to run again,
# and run it again whenever authorized_keys changes.
#
#   .\setup.ps1                   everything below
#   .\setup.ps1 -KeysOnly         just re-copy authorized_keys (a node was added)
#
# What it does, and why each is here rather than a click in Settings:
#
#   1. OpenSSH Server (a Windows optional feature), started at boot. It runs
#      before anyone signs in, so a backup works on a machine that was only
#      woken, which Docker Desktop or a tray app can't do.
#   2. A local account `restic` with a random password nobody keeps: the key is
#      the only way in, and the account is useless for anything else.
#   3. C:\purrbrews\restic for the repository, on the NVMe. restic can write
#      there and nowhere else; C:\purrbrews is its SFTP chroot, so the
#      nodes' BACKUP_REPOSITORY path is /restic.
#   4. sshd_config: `restic` gets SFTP only (internal-sftp in the chroot, no
#      shell, no forwarding, keys only), and AllowUsers restic, so nothing else
#      on this PC can be logged into over SSH at all.
#   5. authorized_keys (beside this script, gitignored) copied to where sshd
#      reads it, with the permissions sshd insists on. One line per node, as
#      `sudo ./backup.sh keys` prints it: from="<ip>",restrict ssh-ed25519 ...
#   6. Windows Firewall: port 22 from the fleet's node addresses only (read
#      from stacks/fleet.env); the feature's own allow-everyone rule is off.
#   7. Power: the USB NIC may wake the PC on a magic packet, and a PC woken
#      with nobody at it stays up for -UnattendedSleepMinutes (Windows' default
#      is 2 minutes, which ends a backup before it starts).
#
param(
    [string]$KeysFile = (Join-Path $PSScriptRoot 'authorized_keys'),
    [string]$Root = 'C:\purrbrews',
    [string]$WakeAdapter = 'zig zag internet',
    [int]$UnattendedSleepMinutes = 180,
    [switch]$KeysOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\_lib\purrbrews.ps1')

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell (Run as administrator).'
}

$User = 'restic'
$Repo = Join-Path $Root 'restic'
$SshDir = Join-Path $env:ProgramData 'ssh'
$SshdConfig = Join-Path $SshDir 'sshd_config'
$SshKeys = Join-Path $SshDir 'restic_authorized_keys'

function Set-StrictAcl([string]$Path) {
    # SYSTEM and Administrators only: what sshd demands of a key file it reads
    # on someone else's behalf.
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($who in 'NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators') {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($who, 'FullControl', 'Allow')))
    }
    $acl.SetOwner((New-Object System.Security.Principal.NTAccount('BUILTIN\Administrators')))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Install-Keys {
    Write-Step 'authorized_keys'
    if (-not (Test-Path -LiteralPath $KeysFile)) {
        throw "No $KeysFile. Copy authorized_keys.example, add each node's line from 'sudo ./backup.sh keys', run this again."
    }
    $lines = @(Get-Content -LiteralPath $KeysFile | Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') })
    foreach ($line in $lines) {
        if ($line -notmatch '^from="[0-9.]+",restrict ssh-ed25519 \S+') {
            throw "authorized_keys: '$line' isn't what 'backup.sh keys' prints (from=`"<ip>`",restrict ssh-ed25519 ...)."
        }
    }
    if ($lines.Count -eq 0) { throw 'authorized_keys has no keys in it.' }
    Write-LFFile $SshKeys $lines
    Set-StrictAcl $SshKeys
    Write-Host "  $($lines.Count) node key(s) -> $SshKeys"
}

if ($KeysOnly) { Install-Keys; return }

# -- 1. OpenSSH Server --------------------------------------------------------
Write-Step 'OpenSSH Server'
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
if ($cap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
    Write-Host "  installed $($cap.Name)"
} else {
    Write-Host '  already installed'
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd   # the first start writes the default sshd_config and host keys

# -- 2. the restic account ----------------------------------------------------
Write-Step "Local account '$User'"
if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $password = ConvertTo-SecureString ([Convert]::ToBase64String($bytes) + 'aA1!') -AsPlainText -Force
    New-LocalUser -Name $User -Password $password -PasswordNeverExpires -AccountNeverExpires `
        -UserMayNotChangePassword -Description 'purrbrews backups: SFTP only, key only' | Out-Null
    Write-Host "  made '$User' (random password, not kept)"
} else {
    Write-Host '  already there'
}

# -- 3. the repository folder -------------------------------------------------
Write-Step "Repository folder $Repo"
New-Item -ItemType Directory -Force -Path $Repo | Out-Null
# The chroot: Administrators/SYSTEM own it, restic may only look inside.
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
foreach ($who in 'NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators') {
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($who, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
}
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($User, 'ReadAndExecute', 'None', 'None', 'Allow')))
Set-Acl -LiteralPath $Root -AclObject $acl
# The repository itself: restic may create, change and delete in here.
$repoAcl = Get-Acl -LiteralPath $Repo
$repoAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($User, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
Set-Acl -LiteralPath $Repo -AclObject $repoAcl
$free = [math]::Round((Get-PSDrive -Name ($Repo.Substring(0, 1))).Free / 1GB)
Write-Host "  $Repo ($free GB free on that drive)"

# -- 4. sshd_config -----------------------------------------------------------
Write-Step 'sshd_config'
$begin = '# BEGIN purrbrews backup target (stacks/roastery/backup-target/setup.ps1)'
$end = '# END purrbrews backup target'
$text = [System.IO.File]::ReadAllText($SshdConfig) -replace "`r`n", "`n"
# Drop any earlier copy of both managed blocks, then put them back.
$text = [regex]::Replace($text, "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))\n?", '')
$global = @($begin, "AllowUsers $User", $end) -join "`n"
$match = @(
    $begin,
    "Match User $User",
    '    AuthorizedKeysFile __PROGRAMDATA__/ssh/restic_authorized_keys',
    "    ChrootDirectory $Root",
    '    ForceCommand internal-sftp',
    '    PasswordAuthentication no',
    '    PubkeyAuthentication yes',
    '    AllowTcpForwarding no',
    '    AllowAgentForwarding no',
    '    PermitTTY no',
    '    X11Forwarding no',
    $end
) -join "`n"
# AllowUsers is global, so it has to sit above the first Match block; the
# Match block goes last, where it can't swallow anything after it.
$first = [regex]::Match($text, '(?m)^Match ')
if ($first.Success) {
    $text = $text.Substring(0, $first.Index) + $global + "`n`n" + $text.Substring($first.Index)
} else {
    $text = $text.TrimEnd() + "`n`n" + $global + "`n"
}
$text = $text.TrimEnd() + "`n`n" + $match + "`n"
$backup = "$SshdConfig.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $SshdConfig -Destination $backup
[System.IO.File]::WriteAllText($SshdConfig, $text)
$sshd = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
& $sshd -t
if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $SshdConfig -Force
    throw "sshd -t rejected the new config; the old one is back ($backup)."
}
Write-Host "  restic: SFTP only, chrooted to $Root, keys only; AllowUsers $User (old config: $backup)"

# -- 5. keys --------------------------------------------------------------------
Install-Keys
Restart-Service sshd

# -- 6. firewall ----------------------------------------------------------------
Write-Step 'Windows Firewall'
$fleet = Read-EnvFile (Join-Path $script:Stacks 'fleet.env')
$nodes = @($fleet.Keys | Where-Object { $_ -match '_LAN_IP$' -and $_ -ne 'ROASTERY_LAN_IP' } | ForEach-Object { $fleet[$_] })
if ($nodes.Count -eq 0) { throw 'No node addresses in stacks/fleet.env.' }
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
Get-NetFirewallRule -Name 'purrbrews-backup-sftp' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name 'purrbrews-backup-sftp' -DisplayName 'purrbrews backups (SFTP from the fleet)' `
    -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress $nodes -Profile Any -Action Allow | Out-Null
Write-Host "  22/tcp from $($nodes -join ', ') only; the default OpenSSH rule is off"

# -- 7. power -------------------------------------------------------------------
Write-Step 'Wake-on-LAN and unattended sleep'
$adapter = Get-NetAdapter -Name $WakeAdapter -ErrorAction SilentlyContinue
if ($adapter) {
    Set-NetAdapterPowerManagement -Name $WakeAdapter -WakeOnMagicPacket Enabled -ErrorAction SilentlyContinue
    & powercfg /deviceenablewake "$($adapter.InterfaceDescription)" 2>$null | Out-Null
    Write-Host "  '$WakeAdapter' ($($adapter.MacAddress)) wakes on a magic packet; that MAC is ROASTERY_WOL_MAC on cellar"
} else {
    Write-Warning "No adapter called '$WakeAdapter'; pass -WakeAdapter <name> (Get-NetAdapter lists them)."
}
# SYSTEM_UNATTENDED_SLEEP_TIMEOUT, hidden by default.
$sleepGroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$unattended = '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'
& powercfg -attributes $sleepGroup $unattended -ATTRIB_HIDE | Out-Null
& powercfg /setacvalueindex SCHEME_CURRENT $sleepGroup $unattended ($UnattendedSleepMinutes * 60) | Out-Null
& powercfg /setactive SCHEME_CURRENT | Out-Null
Write-Host "  woken with nobody at it, it stays up $UnattendedSleepMinutes minutes (on AC)"

# -- done -----------------------------------------------------------------------
Write-Step 'Done'
$hostKey = Join-Path $SshDir 'ssh_host_ed25519_key.pub'
Write-Host 'This host key is what the nodes pin with backup.sh keys; the fingerprints must match:'
& (Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe') -lf $hostKey
Write-Host ''
Write-Host 'Next, on cellar: sudo ./restic/restic-init.sh (once), then sudo ./backup.sh doctor on each node.'
