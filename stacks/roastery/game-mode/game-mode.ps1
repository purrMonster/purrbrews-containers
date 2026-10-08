# game-mode.ps1: keeps llama-swap off the GPU while a game runs.
#
# Every few seconds it looks for a running game (a program under one of
# GAME_PATHS, or named in GAME_EXES; settings in roastery's .env.local) and
# keeps llama-swap's active profile in step:
#   game found      -> profile `gaming` (every model on the CPU), then unload
#                      whatever is loaded, so the VRAM is free at once
#   no game for 60s -> profile `normal`; the GPU model loads again on the next
#                      request, not before
# The grace period stops it flapping while a game restarts or a launcher
# hands over. If llama-swap restarts mid-game it comes back as `normal`, and
# the next poll puts `gaming` back.
#
# The flag other things read is llama-swap's own active profile
# (GET /api/profiles -> "active"): anything that can reach llama-swap can see
# it, and clients that ask for `assistant` or `fast` don't need to look at all.
# state.json beside this script has the same answer for local tools, and
# GAME_MODE_WEBHOOK_URL, when set, is POSTed every change (Home Assistant).
#
# Runs as a scheduled task at logon (install.ps1). By hand:
#   .\game-mode.ps1 -Once    what it sees and would do, changes nothing
#   .\game-mode.ps1          the loop, in the foreground
param(
    [switch]$Once,
    [ValidateRange(2, 300)][int]$PollSeconds = 5,
    [ValidateRange(0, 3600)][int]$ExitGraceSeconds = 60
)

. (Join-Path $PSScriptRoot '..\..\_lib\purrbrews.ps1')
$ErrorActionPreference = 'Stop'

$script:Node = Get-Node (Join-Path $PSScriptRoot '..')
$script:StateFile = Join-Path $PSScriptRoot 'state.json'
$script:LogFile = Join-Path $PSScriptRoot 'game-mode.log'
$script:LastError = ''

function Write-Log([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($Once) { return }
    try {
        Add-Content -LiteralPath $script:LogFile -Value $line
        if ((Get-Item -LiteralPath $script:LogFile).Length -gt 1MB) {
            $keep = Get-Content -LiteralPath $script:LogFile -Tail 2000
            Write-LFFile $script:LogFile $keep
        }
    } catch { }
}

function Split-List([string]$Value) {
    # 'a;b;c' -> a, b, c with / for \, so either spelling matches either.
    if (-not $Value) { return @() }
    return @($Value -split ';' | ForEach-Object { $_.Trim().Replace('\', '/') } | Where-Object { $_ })
}

function Get-Settings {
    $e = Get-EffectiveEnv $script:Node ''
    $url = $e['LLAMA_SWAP_URL']
    if (-not $url) { $url = 'http://127.0.0.1:9292' }
    [pscustomobject]@{
        Url     = $url.TrimEnd('/')
        Paths   = Split-List $e['GAME_PATHS']
        Ignore  = Split-List $e['GAME_IGNORE']
        Exes    = Split-List $e['GAME_EXES']
        Webhook = $e['GAME_MODE_WEBHOOK_URL']
    }
}

function Test-Contains([string]$Text, [string[]]$Fragments) {
    foreach ($f in $Fragments) {
        if ($Text.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Find-Game($Settings) {
    # The first running program that counts as a game, or $null. A process
    # running elevated or as another user has no readable Path from here
    # (some anti-cheat setups start the game that way), so GAME_EXES also
    # matches on the bare process name.
    foreach ($p in Get-Process) {
        $path = $null
        try { $path = $p.Path } catch { }
        if (-not $path) {
            if ($Settings.Exes -contains "$($p.ProcessName).exe") {
                return [pscustomobject]@{ Name = "$($p.ProcessName).exe"; Path = '(not readable)'; Id = $p.Id }
            }
            continue
        }
        $norm = $path.Replace('\', '/')
        $name = [System.IO.Path]::GetFileName($norm)
        $isGame = ($Settings.Exes -contains $name) -or
                  ((Test-Contains $norm $Settings.Paths) -and -not (Test-Contains $norm $Settings.Ignore))
        if ($isGame) {
            return [pscustomobject]@{ Name = $name; Path = $path; Id = $p.Id }
        }
    }
    return $null
}

function Get-SwapProfile($Settings) {
    $r = Invoke-RestMethod -Uri "$($Settings.Url)/api/profiles" -TimeoutSec 5
    return $r.active
}

function Set-SwapProfile($Settings, [string]$Name) {
    $body = @{ name = $Name } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Put -Uri "$($Settings.Url)/api/profiles/active" -Body $body `
        -ContentType 'application/json' -TimeoutSec 10 | Out-Null
}

function Clear-SwapModels($Settings) {
    # Unloads everything; the CPU model is back in seconds if it was wanted.
    Invoke-RestMethod -Method Post -Uri "$($Settings.Url)/api/models/unload" -TimeoutSec 60 | Out-Null
}

function Sync-Swap($Settings, [bool]$Gaming) {
    # Make llama-swap agree with $Gaming. Quiet while it's down (Docker Desktop
    # still starting, say): one log line per new error, not one per poll.
    $want = if ($Gaming) { 'gaming' } else { 'normal' }
    try {
        $active = Get-SwapProfile $Settings
        if ($active -ne $want) {
            Set-SwapProfile $Settings $want
            if ($Gaming) { Clear-SwapModels $Settings }
            Write-Log "llama-swap: profile $active -> $want$(if ($Gaming) { ', models unloaded' })"
        }
        if ($script:LastError) { Write-Log 'llama-swap: reachable again'; $script:LastError = '' }
        return $want
    } catch {
        $msg = $_.Exception.Message
        if ($msg -ne $script:LastError) { Write-Log "llama-swap: not reachable ($msg); retrying every poll" }
        $script:LastError = $msg
        return $null
    }
}

function Send-Webhook($Settings, $State) {
    if (-not $Settings.Webhook) { return }
    try {
        $body = [ordered]@{ gaming = $State.gaming; game = $State.game; since = $State.since; host = $env:COMPUTERNAME } |
            ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post -Uri $Settings.Webhook -Body $body -ContentType 'application/json' -TimeoutSec 10 | Out-Null
    } catch {
        # The URL is a secret: never logged, only the failure.
        Write-Log "webhook failed: $($_.Exception.Message)"
    }
}

function Save-State($State) {
    $json = $State | ConvertTo-Json -Compress
    Write-LFFile $script:StateFile @($json)
}

# ---- -Once: report and change nothing -----------------------------------------
if ($Once) {
    $s = Get-Settings
    Write-Host "llama-swap:  $($s.Url)"
    Write-Host "game paths:  $($s.Paths -join '; ')"
    Write-Host "ignored:     $($s.Ignore -join '; ')"
    Write-Host "game exes:   $(if ($s.Exes) { $s.Exes -join '; ' } else { '(none)' })"
    Write-Host "webhook:     $(if ($s.Webhook) { 'set' } else { 'off' })"
    $game = Find-Game $s
    if ($game) { Write-Host "game:        $($game.Name) (pid $($game.Id)) $($game.Path)" } else { Write-Host 'game:        none running' }
    try { $active = Get-SwapProfile $s; Write-Host "profile now: $active" } catch { Write-Host "profile now: llama-swap not reachable ($($_.Exception.Message))" }
    Write-Host "would set:   $(if ($game) { 'gaming, and unload models' } else { 'normal (after the grace period)' })"
    exit 0
}

# ---- The loop ---------------------------------------------------------------------
# One copy only, whether started by the task or by hand.
$mutex = New-Object System.Threading.Mutex($false, 'Local\purrbrews-game-mode')
if (-not $mutex.WaitOne(0)) { Write-Host 'game-mode is already running.'; exit 0 }

$state = [ordered]@{ gaming = $false; game = $null; since = (Get-Date).ToString('o'); profile = $null; updated = $null }
$lastSeen = [datetime]::MinValue
Write-Log "game-mode started (poll ${PollSeconds}s, grace ${ExitGraceSeconds}s)"

try {
    while ($true) {
        try {
            $settings = Get-Settings
            $now = Get-Date
            $game = Find-Game $settings
            if ($game) { $lastSeen = $now }
            $gaming = [bool]$game -or ($state.gaming -and ($now - $lastSeen).TotalSeconds -lt $ExitGraceSeconds)

            if ($gaming -ne $state.gaming) {
                $state.gaming = $gaming
                $state.game = if ($game) { $game.Name } else { $null }
                $state.since = $now.ToString('o')
                if ($gaming) { Write-Log "game started: $($game.Name) ($($game.Path))" } else { Write-Log 'no game for the grace period: back to normal' }
                Send-Webhook $settings $state
            } elseif ($gaming -and $game -and $state.game -ne $game.Name) {
                $state.game = $game.Name
            }

            $state.profile = Sync-Swap $settings $gaming
            $state.updated = $now.ToString('o')
            Save-State $state
        } catch {
            Write-Log "error: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds $PollSeconds
    }
} finally {
    $mutex.ReleaseMutex()
}
