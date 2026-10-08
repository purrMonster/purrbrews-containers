# fill-vault.ps1: copy the fleet's secrets into flask.kdbx (docs/flask.md,
# "What goes in the vault"), straight from each node into KeePassXC.
#
#   .\fill-vault.ps1                         the vault on the stick labelled FLASK-A
#   .\fill-vault.ps1 -Vault E:\flask.kdbx    a specific vault
#   .\fill-vault.ps1 -DryRun                 which entries it would write, and from where;
#                                            no vault, no password, no values shown
#
# Make the vault first, in KeePassXC (the GUI): that's where you choose the
# master password and see the settings. This only adds entries to it.
#
# The values never reach the screen, a file or the clipboard: each one is read
# over SSH (as barista, with your key) into memory and handed to keepassxc-cli
# on its standard input. The master password is typed once, hidden. Safe to run
# again: it compares each entry with the node and rewrites only the ones whose
# value has changed (and adds new ones), so this is also how the vault is
# brought up to date after a secret changes. Notes you've edited by hand, and
# entries it doesn't know about, are left alone.
#
# Not covered, add them by hand: barista's sudo password on each node,
# roastery's Windows password, the 2FA recovery codes, and (once Drive is set
# up) cellar's /etc/purrbrews/rclone.conf as an attachment.
#
param([string]$Vault, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\_lib\purrbrews.ps1')

# name -> tier group, as in docs/flask.md. Keep the two lists in step.
$Tiers = [ordered]@{
    'Tier 1' = 'RESTIC_PASSWORD', 'RCLONE_CRYPT_PASSWORD', 'RCLONE_CRYPT_SALT'
    'Tier 2' = 'N8N_ENCRYPTION_KEY', 'AUTHELIA_STORAGE_ENCRYPTION_KEY', 'LLDAP_KEY_SEED', 'LLDAP_JWT_SECRET',
               'PAPERLESS_SECRET_KEY', 'FRESHRSS_OIDC_CRYPTO_KEY', 'SPEEDTEST_TRACKER_APP_KEY',
               'KOMODO_DATABASE_PASSWORD', 'KOMODO_JWT_SECRET'
    'Tier 3' = 'LLDAP_ADMIN_PASSWORD', 'PAPERLESS_ADMIN_PASSWORD', 'NEXTCLOUD_ADMIN_PASSWORD',
               'VAULTWARDEN_ADMIN_PASSWORD', 'KOMODO_INIT_ADMIN_PASSWORD', 'PIHOLE_WEBPASSWORD',
               'NTFY_ADMIN_PASSWORD', 'ESPHOME_DASHBOARD_PASSWORD', 'SPEEDTEST_TRACKER_ADMIN_PASSWORD',
               'SMB_BARISTA_PASSWORD'
    'Tier 4' = 'CF_DNS_API_TOKEN', 'TUNNEL_TOKEN', 'RCLONE_DRIVE_CLIENT_ID', 'RCLONE_DRIVE_CLIENT_SECRET',
               'HEALTHCHECKS_PING_URL', 'NTFY_URL'
}
$Nodes = 'sieve', 'percolator', 'cellar', 'mochaPot', 'grinder'
# Different on every node on purpose (the owner, 2026-09-29): one entry per node,
# no warning. Anything else that differs between nodes is worth a look.
$PerNode = @('CF_DNS_API_TOKEN')

# -- the vault and keepassxc-cli ---------------------------------------------------
if ($DryRun) { $Vault = '(dry run)' }
elseif (-not $Vault) {
    $vol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'FLASK-A' -and $_.DriveLetter } | Select-Object -First 1
    if (-not $vol) { throw 'No FLASK-A stick plugged in; plug it in, or give -Vault <path>.' }
    $Vault = "$($vol.DriveLetter):\flask.kdbx"
}
if (-not $DryRun -and -not (Test-Path -LiteralPath $Vault)) {
    throw "No vault at $Vault. Make it in KeePassXC first (Database > New Database), then run this again."
}
$cli = if ($DryRun) { 'none' } else { @((Join-Path (Split-Path -Qualifier $Vault) 'tools\windows-amd64\KeePassXC\keepassxc-cli.exe'),
         (Join-Path $env:LOCALAPPDATA 'purrbrews\flask\stage\tools\windows-amd64\KeePassXC\keepassxc-cli.exe'),
         (Join-Path $env:ProgramFiles 'KeePassXC\keepassxc-cli.exe')) |
       Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
if (-not $cli) { throw 'keepassxc-cli.exe not found (it comes with KeePassXC; make-flask.ps1 puts it on the stick).' }

function Invoke-Kpx([string[]]$ArgList, [string[]]$Stdin) {
    # keepassxc-cli reads the master password, then any entry password, from
    # standard input, one per line. Its output is never shown: it's only
    # prompts, and `show` would be a value.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = ($Stdin -join "`n") | & $script:cli @ArgList 2>&1 } finally { $ErrorActionPreference = $old }
    $LASTEXITCODE
}

function Get-KpxPassword([string]$Path) {
    # An entry's current password, for comparing, never for showing. $null if
    # there's no such entry.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @($script:Master | & $script:cli show -q -s -a Password $Vault $Path 2>$null) } finally { $ErrorActionPreference = $old }
    if ($LASTEXITCODE -ne 0) { return $null }
    $out -join "`n"
}

function Get-EntryTitle([string]$Name, [string]$Where, [string[]]$AllWheres) {
    # keepassxc-cli reads / in an entry path as a group, so a title never has
    # one: "CF_DNS_API_TOKEN (sieve)", or "(sieve traefik)" if that node has
    # the key in two apps.
    $node = ($Where -split '/')[0]
    $sameNode = @($AllWheres | Where-Object { ($_ -split '/')[0] -eq $node }).Count
    $label = if ($sameNode -gt 1) { $Where -replace '/', ' ' } else { $node }
    "$Name ($label)"
}

if (-not $DryRun) {
    $secure = Read-Host "Master password for $Vault" -AsSecureString
    $Master = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if ((Invoke-Kpx @('ls', '-q', $Vault) @($Master)) -ne 0) { throw "That password doesn't open $Vault." }
}

# -- read the secrets from the nodes -----------------------------------------------
Write-Step 'Reading the nodes (values stay in memory)'
$fleet = Read-EnvFile (Join-Path $script:Stacks 'fleet.env')
$pattern = ($Tiers.Values | ForEach-Object { $_ }) -join '|'
$found = @{}   # name -> list of @{ Where; Value }
foreach ($node in $Nodes) {
    $ip = $fleet["$($node.ToUpper())_LAN_IP"]
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& ssh -o BatchMode=yes "barista@$ip" "grep -HE '^($pattern)=' /opt/purrbrews/stacks/*/*/secrets.env.local /opt/purrbrews/stacks/*/.env.local 2>/dev/null" 2>$null)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    if ($code -gt 1) { Write-Warning "  $node ($ip): couldn't read it over SSH; its secrets are missing from this run."; continue }
    foreach ($line in $lines) {
        if ($line -notmatch '^/opt/purrbrews/stacks/([^/]+)/(?:([^/]+)/)?[^/:]+:([A-Z0-9_]+)=(.*)$') { continue }
        $where = if ($Matches[2]) { "$($Matches[1])/$($Matches[2])" } else { "$($Matches[1])/.env.local" }
        $name, $value = $Matches[3], $Matches[4]
        if ($value -match "^'(.*)'$" -or $value -match '^"(.*)"$') { $value = $Matches[1] }
        if (Test-Placeholder $value) { continue }
        if (-not $found.ContainsKey($name)) { $found[$name] = New-Object System.Collections.ArrayList }
        [void]$found[$name].Add(@{ Where = $where; Value = $value })
    }
    Write-Host "  $node`: $(@($lines).Count) line(s)"
}

# -- write them -----------------------------------------------------------------------
Write-Step "Writing $Vault"
$added = 0; $updated = 0; $same = 0; $failed = @(); $missing = @()
foreach ($group in $Tiers.Keys) {
    if (-not $DryRun) { $null = Invoke-Kpx @('mkdir', '-q', $Vault, $group) @($Master) }   # fails harmlessly if it's there
    foreach ($name in $Tiers[$group]) {
        if (-not $found.ContainsKey($name)) { $missing += $name; continue }
        # The same key on several nodes (RESTIC_PASSWORD) is one entry when every
        # copy agrees, one per node when they don't, or when it's per node anyway.
        $byValue = $found[$name] | Group-Object { $_.Value }
        $entries = if (@($byValue).Count -eq 1 -and $PerNode -notcontains $name) {
            @{ Title = $name; Value = $found[$name][0].Value; Notes = (($found[$name] | ForEach-Object { $_.Where }) -join ', ') }
        } else {
            if ($PerNode -notcontains $name) { Write-Warning "  $name differs between nodes; one entry per node. Worth finding out why." }
            $wheres = @($found[$name] | ForEach-Object { $_.Where })
            $found[$name] | ForEach-Object { @{ Title = (Get-EntryTitle $name $_.Where $wheres); Value = $_.Value; Notes = $_.Where } }
        }
        foreach ($e in $entries) {
            $path = "$group/$($e.Title)"
            if ($DryRun) { Write-Host "  would write  $path  ($($e.Notes))"; continue }
            $current = Get-KpxPassword $path
            if ($null -ne $current -and $current -ceq $e.Value) {
                $same++
            } elseif ($null -ne $current) {
                $rc = Invoke-Kpx @('edit', '-q', '-p', $Vault, $path) @($Master, $e.Value)
                if ($rc -eq 0) { $updated++; Write-Host "  changed  $path  (the node has a new value)" } else { $failed += $path }
            } else {
                $rc = Invoke-Kpx @('add', '-q', '-p', '--notes', $e.Notes, $Vault, $path) @($Master, $e.Value)
                if ($rc -eq 0) { $added++; Write-Host "  added    $path  ($($e.Notes))" } else { $failed += $path }
            }
        }
    }
}
$Master = $null; $script:Master = $null; $found = $null; $current = $null
[GC]::Collect()

Write-Step 'Done'
if ($DryRun) { Write-Host '  Dry run: nothing was written.' }
else { Write-Host "  $added added, $updated changed, $same already up to date." }
if ($missing) { Write-Host "  Not set on any node (fine if that app or Drive isn't set up yet): $($missing -join ', ')" }
if ($failed) { Write-Warning "  keepassxc-cli refused: $($failed -join ', ')"; exit 1 }
Write-Host ''
Write-Host 'Still by hand, in KeePassXC: sudo passwords, roastery''s Windows password, 2FA recovery codes,'
Write-Host 'and rclone.conf once Drive is set up. Then copy flask.kdbx to FLASK-B and run .\make-flask.ps1 -Check.'
