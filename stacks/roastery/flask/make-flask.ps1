# make-flask.ps1: build or check flask, the offline recovery kit (docs/flask.md).
# Runs on roastery from a normal PowerShell; no admin needed.
#
#   .\make-flask.ps1                 download, verify, and write every flask stick plugged in
#   .\make-flask.ps1 -PrepareOnly    download and verify only; no stick needed
#   .\make-flask.ps1 -Check          no downloads: check each stick against its SHA256SUMS
#                                    and compare the two vaults (the yearly check)
#
# A flask stick is a USB disk with Ventoy on it (its VTOYEFI partition is how
# this tells) and an exFAT data partition labelled FLASK-A or FLASK-B. Nothing
# else is ever written to, so an internal disk or an unlabelled stick is safe.
#
# What goes on each stick (docs/flask.md, "Layout of each stick"):
#
#   debian-live-<ver>-amd64-xfce.iso   Ventoy boots it
#   tools\linux-amd64\                  restic, rclone, KeePassXC AppImage
#   tools\windows-amd64\                restic.exe, rclone.exe, KeePassXC\ (portable)
#   tools\darwin-arm64\, darwin-amd64\  restic, rclone
#   RECOVERY.md, VERSIONS.txt
#   SHA256SUMS                          every file above; `sha256sum -c SHA256SUMS` on Linux
#
# flask.kdbx is never read, written or listed in SHA256SUMS: the vault is filled
# by hand in KeePassXC. -Check only compares its hash between the sticks, so
# you know whether B still matches A.
#
# Trust: every download is checked against its project's signed checksums, and
# the signature against the key fingerprints pinned below (from each project's
# own docs, 2026-09-28). A key is fetched from a keyserver but only accepted if
# its fingerprint matches. Anything that doesn't verify stops the run before a
# stick is touched. gpg and bzip2 come with Git for Windows.
#
# The versions are pinned too; bump them at the yearly check (runbook).
#
param(
    [switch]$PrepareOnly,
    [switch]$Check,
    [string]$Cache = (Join-Path $env:LOCALAPPDATA 'purrbrews\flask'),
    [string]$DebianVersion = '13.7.0',
    [string]$ResticVersion = '0.19.1',
    [string]$RcloneVersion = '1.75.1',
    [string]$KeePassXCVersion = '2.7.12'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\_lib\purrbrews.ps1')

$Keys = @{
    debian    = 'DF9B9C49EAA9298432589D76DA87E80D6294BE9B'   # Debian CD signing key (debian.org/CD/verify)
    restic    = 'CF8F18F2844575973F79D4E191A6868BD3F7A907'   # Alexander Neumann (restic docs, Installation)
    rclone    = 'FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA'   # Nick Craig-Wood (rclone.org/release_signing)
    keepassxc = 'BF5A669F2272CF4324C1FDA8CFB4C2166397D0D2'   # KeePassXC master key (keepassxc.org/verifying-signatures)
}
$Excluded = '^(flask\.kdbx.*|SHA256SUMS|System Volume Information[\\/].*|ventoy[\\/].*)$'

# -- helpers --------------------------------------------------------------------
function Find-Exe([string]$Name) {
    foreach ($dir in "$env:ProgramFiles\Git\usr\bin", "$env:ProgramFiles\Git\mingw64\bin") {
        $p = Join-Path $dir "$Name.exe"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw "$Name isn't installed. It comes with Git for Windows (winget install Git.Git)."
}

function Invoke-Exe([string]$Exe, [string[]]$ArgList) {
    # Native tools write progress to stderr; PowerShell 5 would turn that into
    # errors under 'Stop', so collect it as text and judge by the exit code.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $Exe @ArgList 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $old }
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

function Unix([string]$Path) {
    # Git's gpg and bzip2 are MSYS programs: C:\x\y must be /c/x/y, or they take
    # it for a relative path.
    if ($Path -match '^([A-Za-z]):\\(.*)$') { return '/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/') }
    $Path -replace '\\', '/'
}

function Get-Download([string]$Url, [string]$Dest) {
    if (Test-Path -LiteralPath $Dest) { return }
    $part = "$Dest.part"
    # Not through Invoke-Exe: curl's progress bar should reach the screen, and an
    # unredirected stderr does, even in PowerShell 5. -C - resumes a broken download.
    Write-Host "  downloading $(Split-Path -Leaf $Dest)"
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $script:Curl -fL --retry 3 -C - --progress-bar -o $part $Url; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "Download failed (curl $code): $Url" }
    Move-Item -LiteralPath $part -Destination $Dest -Force
}

function Import-PinnedKey([string]$Fingerprint) {
    $file = Join-Path $script:Work "$Fingerprint.asc"
    $url = "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$Fingerprint"
    $r = Invoke-Exe $script:Curl @('-fsSL', '--retry', '3', '-o', $file, $url)
    if ($r.Code -ne 0) { throw "Couldn't fetch key $Fingerprint from keyserver.ubuntu.com." }
    $null = Invoke-Exe $script:Gpg @('--homedir', $script:GpgHome, '--batch', '--import', (Unix $file))
    $r = Invoke-Exe $script:Gpg @('--homedir', $script:GpgHome, '--batch', '--with-colons', '--fingerprint', $Fingerprint)
    $fprs = $r.Out | Where-Object { $_ -like 'fpr:*' } | ForEach-Object { ($_ -split ':')[9] }
    if ($r.Code -ne 0 -or $fprs -notcontains $Fingerprint) { throw "Key $Fingerprint didn't import as that fingerprint; not trusting it." }
}

function Assert-Signature([string[]]$GpgArgs, [string[]]$Allowed, [string]$What) {
    # Good only if gpg says GOODSIG and VALIDSIG's primary-key fingerprint (its
    # last field) is one we pinned. Not good enough: any key in the keyring.
    $r = Invoke-Exe $script:Gpg (@('--homedir', $script:GpgHome, '--batch', '--status-fd', '1') + $GpgArgs)
    $good = $r.Out | Where-Object { $_.StartsWith('[GNUPG:] GOODSIG ') }
    $primary = $r.Out | Where-Object { $_.StartsWith('[GNUPG:] VALIDSIG ') } | ForEach-Object { ($_ -split ' ')[-1] }
    if ($r.Code -ne 0 -or -not $good -or -not ($primary | Where-Object { $Allowed -contains $_ })) {
        $r.Out | Where-Object { -not $_.StartsWith('[GNUPG:]') } | ForEach-Object { Write-Host "    $_" }
        throw "$What`: signature not good, or not by a pinned key. Stopping; no stick was touched."
    }
    Write-Host "  $What`: signature good ($($primary | Select-Object -First 1))"
}

function Read-Sums([string]$Path) {
    $sums = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^([0-9a-fA-F]{64}|[0-9a-fA-F]{128})\s+\*?(?:\./)?(\S+)$') { $sums[$Matches[2]] = $Matches[1].ToLower() }
    }
    $sums
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Algorithm = 'SHA256') {
    $name = Split-Path -Leaf $Path
    if (-not $Expected) { throw "No published checksum for $name." }
    $got = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLower()
    if ($got -ne $Expected) {
        Remove-Item -LiteralPath $Path -Force
        throw "$name`: checksum mismatch (deleted; run again to download it fresh)."
    }
    Write-Host "  $name`: $Algorithm matches"
}

function Get-FlaskSticks {
    foreach ($vol in Get-Volume | Where-Object { $_.FileSystemLabel -match '^FLASK-[AB]$' -and $_.DriveLetter }) {
        $part = Get-Partition -DriveLetter $vol.DriveLetter
        $disk = Get-Disk -Number $part.DiskNumber
        $labels = Get-Partition -DiskNumber $disk.Number | Get-Volume -ErrorAction SilentlyContinue | ForEach-Object { $_.FileSystemLabel }
        if ($disk.BusType -ne 'USB') { Write-Warning "$($vol.FileSystemLabel) isn't on a USB disk; skipped."; continue }
        if ($labels -notcontains 'VTOYEFI') { Write-Warning "$($vol.FileSystemLabel) has no Ventoy on it (no VTOYEFI partition); install Ventoy first. Skipped."; continue }
        if ($vol.FileSystem -ne 'exFAT') { Write-Warning "$($vol.FileSystemLabel) is $($vol.FileSystem), not exFAT; skipped."; continue }
        [pscustomobject]@{ Label = $vol.FileSystemLabel; Root = "$($vol.DriveLetter):\"; Disk = "$($disk.FriendlyName) #$($disk.Number)" }
    }
}

function Get-TreeSums([string]$Root) {
    # relative/path -> sha256, for every file under $Root except the excluded ones.
    $sums = [ordered]@{}
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($Root.TrimEnd('\').Length + 1) -replace '\\', '/'
        if ($rel -notmatch $Excluded) { $sums[$rel] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() }
    }
    $sums
}

function Test-Stick($Stick) {
    $sumsFile = Join-Path $Stick.Root 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $sumsFile)) { Write-Warning "  $($Stick.Label): no SHA256SUMS; it has never been built."; return $false }
    $want = Read-Sums $sumsFile
    $have = Get-TreeSums $Stick.Root
    $bad = @()
    foreach ($k in $want.Keys) { if ($have[$k] -ne $want[$k]) { $bad += "changed or missing: $k" } }
    # Something you added by hand (a second ISO, say) is only a note: it isn't
    # part of the kit, and nothing here should make you delete it.
    foreach ($k in $have.Keys) { if (-not $want.ContainsKey($k)) { Write-Host "  $($Stick.Label): not part of the kit (left alone): $k" } }
    if ($bad) { $bad | ForEach-Object { Write-Warning "  $($Stick.Label): $_" }; return $false }
    Write-Host "  $($Stick.Label): all $($want.Count) files match SHA256SUMS"
    $true
}

function Compare-Vaults($Sticks) {
    $vaults = @{}
    foreach ($s in $Sticks) {
        $v = Join-Path $s.Root 'flask.kdbx'
        if (Test-Path -LiteralPath $v) { $vaults[$s.Label] = (Get-FileHash -LiteralPath $v -Algorithm SHA256).Hash }
        else { Write-Warning "  $($s.Label): no flask.kdbx yet." }
    }
    if ($vaults.Count -eq 2) {
        if (@($vaults.Values | Select-Object -Unique).Count -eq 1) { Write-Host '  flask.kdbx: the same on both sticks' }
        else { Write-Warning '  flask.kdbx differs between the sticks: copy the newer one (A, by the runbook) over the other.' }
    }
}

# -- sticks ---------------------------------------------------------------------
$sticks = @(Get-FlaskSticks)
if ($Check) {
    Write-Step 'Checking the sticks'
    if (-not $sticks) { throw 'No flask stick plugged in (FLASK-A or FLASK-B, with Ventoy).' }
    $ok = $true
    foreach ($s in $sticks) { if (-not (Test-Stick $s)) { $ok = $false } }
    Compare-Vaults $sticks
    if (-not $ok) { throw 'At least one stick failed its check: rebuild it with .\make-flask.ps1, then refill or copy its vault.' }
    Write-Host ''
    Write-Host 'All good. Unplug them and put them back in their places.'
    return
}
if (-not $PrepareOnly -and -not $sticks) {
    throw 'No flask stick plugged in (FLASK-A or FLASK-B, with Ventoy). -PrepareOnly downloads and verifies without one.'
}

# -- download and verify ----------------------------------------------------------
$script:Curl = Find-Exe 'curl'
$script:Gpg = Find-Exe 'gpg'
$Bzip2 = Find-Exe 'bzip2'
$Downloads = Join-Path $Cache 'downloads'
$script:Work = Join-Path $Cache "work-$PID"
$script:GpgHome = Unix (Join-Path $script:Work 'gnupg')
New-Item -ItemType Directory -Force -Path $Downloads, (Join-Path $script:Work 'gnupg') | Out-Null

try {
    Write-Step 'Signing keys (pinned fingerprints)'
    foreach ($k in $Keys.Values) { Import-PinnedKey $k }
    Write-Host "  $($Keys.Count) keys imported, fingerprints match"

    # Debian Live: the current release sits in debian-cd/, older ones in archive/.
    Write-Step "Debian Live $DebianVersion (xfce)"
    $iso = "debian-live-$DebianVersion-amd64-xfce.iso"
    $dd = Join-Path $Downloads "debian-$DebianVersion"
    New-Item -ItemType Directory -Force -Path $dd | Out-Null
    $bases = "https://cdimage.debian.org/debian-cd/$DebianVersion-live/amd64/iso-hybrid",
             "https://cdimage.debian.org/cdimage/archive/$DebianVersion-live/amd64/iso-hybrid"
    $base = $null
    foreach ($b in $bases) {
        try { Get-Download "$b/SHA512SUMS" (Join-Path $dd 'SHA512SUMS'); $base = $b; break } catch { }
    }
    if (-not $base) { throw "Debian $DebianVersion live isn't on cdimage.debian.org (current or archive)." }
    Get-Download "$base/SHA512SUMS.sign" (Join-Path $dd 'SHA512SUMS.sign')
    Assert-Signature @('--verify', (Unix (Join-Path $dd 'SHA512SUMS.sign')), (Unix (Join-Path $dd 'SHA512SUMS'))) @($Keys.debian) 'Debian SHA512SUMS'
    Get-Download "$base/$iso" (Join-Path $dd $iso)
    Assert-Hash (Join-Path $dd $iso) (Read-Sums (Join-Path $dd 'SHA512SUMS'))[$iso] 'SHA512'
    $IsoPath = Join-Path $dd $iso

    Write-Step "restic $ResticVersion"
    $rd = Join-Path $Downloads "restic-$ResticVersion"
    New-Item -ItemType Directory -Force -Path $rd | Out-Null
    $rbase = "https://github.com/restic/restic/releases/download/v$ResticVersion"
    Get-Download "$rbase/SHA256SUMS" (Join-Path $rd 'SHA256SUMS')
    Get-Download "$rbase/SHA256SUMS.asc" (Join-Path $rd 'SHA256SUMS.asc')
    Assert-Signature @('--verify', (Unix (Join-Path $rd 'SHA256SUMS.asc')), (Unix (Join-Path $rd 'SHA256SUMS'))) @($Keys.restic) 'restic SHA256SUMS'
    $rsums = Read-Sums (Join-Path $rd 'SHA256SUMS')
    $restic = @{ 'linux-amd64' = "restic_${ResticVersion}_linux_amd64.bz2"; 'darwin-arm64' = "restic_${ResticVersion}_darwin_arm64.bz2";
                 'darwin-amd64' = "restic_${ResticVersion}_darwin_amd64.bz2"; 'windows-amd64' = "restic_${ResticVersion}_windows_amd64.zip" }
    foreach ($f in $restic.Values) { Get-Download "$rbase/$f" (Join-Path $rd $f); Assert-Hash (Join-Path $rd $f) $rsums[$f] }

    Write-Step "rclone $RcloneVersion"
    $cd = Join-Path $Downloads "rclone-$RcloneVersion"
    New-Item -ItemType Directory -Force -Path $cd | Out-Null
    $cbase = "https://downloads.rclone.org/v$RcloneVersion"
    Get-Download "$cbase/SHA256SUMS" (Join-Path $cd 'SHA256SUMS.signed')
    # Clearsigned: read the hashes from what gpg says was signed, not from the file.
    $plain = Join-Path $script:Work 'rclone-SHA256SUMS'
    Assert-Signature @('-o', (Unix $plain), '--decrypt', (Unix (Join-Path $cd 'SHA256SUMS.signed'))) @($Keys.rclone) 'rclone SHA256SUMS'
    $csums = Read-Sums $plain
    $rclone = @{ 'linux-amd64' = "rclone-v$RcloneVersion-linux-amd64.zip"; 'darwin-arm64' = "rclone-v$RcloneVersion-osx-arm64.zip";
                 'darwin-amd64' = "rclone-v$RcloneVersion-osx-amd64.zip"; 'windows-amd64' = "rclone-v$RcloneVersion-windows-amd64.zip" }
    foreach ($f in $rclone.Values) { Get-Download "$cbase/$f" (Join-Path $cd $f); Assert-Hash (Join-Path $cd $f) $csums[$f] }

    Write-Step "KeePassXC $KeePassXCVersion"
    $kd = Join-Path $Downloads "keepassxc-$KeePassXCVersion"
    New-Item -ItemType Directory -Force -Path $kd | Out-Null
    $kbase = "https://github.com/keepassxreboot/keepassxc/releases/download/$KeePassXCVersion"
    $appimage = "KeePassXC-$KeePassXCVersion-x86_64.AppImage"
    $winzip = "KeePassXC-$KeePassXCVersion-Win64.zip"
    foreach ($f in $appimage, $winzip) {
        Get-Download "$kbase/$f.sig" (Join-Path $kd "$f.sig")
        Get-Download "$kbase/$f" (Join-Path $kd $f)
        try {
            Assert-Signature @('--verify', (Unix (Join-Path $kd "$f.sig")), (Unix (Join-Path $kd $f))) @($Keys.keepassxc) $f
        } catch { Remove-Item -LiteralPath (Join-Path $kd $f) -Force; throw }
    }

    # -- stage: the tools tree exactly as it goes on the stick --------------------
    Write-Step 'Staging the tools'
    $Stage = Join-Path $Cache 'stage'
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    $tools = Join-Path $Stage 'tools'
    foreach ($p in 'linux-amd64', 'darwin-arm64', 'darwin-amd64', 'windows-amd64') {
        $dir = Join-Path $tools $p
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        # restic
        $src = Join-Path $rd $restic[$p]
        if ($src.EndsWith('.zip')) {
            $x = Join-Path $script:Work "restic-$p"
            Expand-Archive -LiteralPath $src -DestinationPath $x -Force
            Copy-Item -LiteralPath (Get-ChildItem -LiteralPath $x -Recurse -Filter 'restic*.exe' | Select-Object -First 1).FullName (Join-Path $dir 'restic.exe')
        } else {
            $tmp = Join-Path $script:Work $restic[$p]
            Copy-Item -LiteralPath $src $tmp
            $r = Invoke-Exe $Bzip2 @('-d', '-f', (Unix $tmp))
            if ($r.Code -ne 0) { throw "bzip2 couldn't unpack $($restic[$p])." }
            Move-Item -LiteralPath ($tmp -replace '\.bz2$', '') (Join-Path $dir 'restic')
        }
        # rclone
        $x = Join-Path $script:Work "rclone-$p"
        Expand-Archive -LiteralPath (Join-Path $cd $rclone[$p]) -DestinationPath $x -Force
        $exe = if ($p -eq 'windows-amd64') { 'rclone.exe' } else { 'rclone' }
        Copy-Item -LiteralPath (Get-ChildItem -LiteralPath $x -Recurse -File | Where-Object Name -eq $exe | Select-Object -First 1).FullName (Join-Path $dir $exe)
    }
    Copy-Item -LiteralPath (Join-Path $kd $appimage) (Join-Path $tools "linux-amd64\$appimage")
    Expand-Archive -LiteralPath (Join-Path $kd $winzip) -DestinationPath (Join-Path $script:Work 'kpx') -Force
    # The zip holds one KeePassXC-<ver>-Win64 folder; copy what's inside it.
    $kpx = Join-Path $script:Work 'kpx'
    $inner = @(Get-ChildItem -LiteralPath $kpx)
    if ($inner.Count -eq 1 -and $inner[0].PSIsContainer) { $kpx = $inner[0].FullName }
    Copy-Item -Path (Join-Path $kpx '*') -Destination (New-Item -ItemType Directory -Force -Path (Join-Path $tools 'windows-amd64\KeePassXC')).FullName -Recurse
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RECOVERY.md') (Join-Path $Stage 'RECOVERY.md')
    Write-LFFile (Join-Path $Stage 'VERSIONS.txt') @(
        "flask built $(Get-Date -Format 'yyyy-MM-dd') by stacks/roastery/flask/make-flask.ps1",
        "Debian Live $DebianVersion (xfce)   $iso",
        "restic      $ResticVersion",
        "rclone      $RcloneVersion",
        "KeePassXC   $KeePassXCVersion",
        'Every file was checked against its project''s signed checksums; SHA256SUMS lists them all.')
    Write-Host "  staged in $Stage"
} finally {
    if (Test-Path -LiteralPath $script:Work) {
        try { $null = Invoke-Exe (Find-Exe 'gpgconf') @('--homedir', $script:GpgHome, '--kill', 'all') } catch { }
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($PrepareOnly) {
    Write-Host ''
    Write-Host "Everything downloaded and verified. Plug in the sticks and run .\make-flask.ps1 to write them."
    return
}

# -- write each stick ---------------------------------------------------------------
$stageSums = Get-TreeSums $Stage
$isoSum = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash.ToLower()
foreach ($s in $sticks) {
    Write-Step "Writing $($s.Label) ($($s.Root), $($s.Disk))"
    # tools\ is mirrored (old versions go); nothing else on the stick is removed
    # except older Debian ISOs. flask.kdbx is never touched.
    $r = Invoke-Exe 'robocopy.exe' @((Join-Path $Stage 'tools'), (Join-Path $s.Root 'tools'), '/MIR', '/R:2', '/W:2', '/NJH', '/NJS', '/NDL', '/NFL', '/NP')
    if ($r.Code -ge 8) { $r.Out | ForEach-Object { Write-Host "    $_" }; throw "robocopy failed writing tools to $($s.Label)." }
    foreach ($f in 'RECOVERY.md', 'VERSIONS.txt') { Copy-Item -LiteralPath (Join-Path $Stage $f) (Join-Path $s.Root $f) -Force }
    Get-ChildItem -LiteralPath $s.Root -Filter 'debian-live-*.iso' -File | Where-Object Name -ne $iso | Remove-Item -Force
    $target = Join-Path $s.Root $iso
    if (-not (Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower() -ne $isoSum) {
        Write-Host "  copying $iso (a few minutes)"
        Copy-Item -LiteralPath $IsoPath $target -Force
    }
    $lines = @("$isoSum  $iso") + @($stageSums.Keys | ForEach-Object { "$($stageSums[$_])  $_" })
    Write-LFFile (Join-Path $s.Root 'SHA256SUMS') $lines
    # Read everything back from the stick: a bad write shows up now, not on the worst day.
    if (-not (Test-Stick $s)) { throw "$($s.Label) doesn't read back what was written. Try another USB port; if it happens again, replace the stick." }
}

Write-Step 'Vaults'
Compare-Vaults $sticks
Write-Host ''
Write-Host 'Done. Next (docs/flask.md): fill flask.kdbx in KeePassXC on A, copy it to B, run .\make-flask.ps1 -Check,'
Write-Host 'then eject both from the tray before pulling them out.'
