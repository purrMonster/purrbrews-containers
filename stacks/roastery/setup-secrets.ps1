<#
.SYNOPSIS
    First-time-setup script for roastery -- PowerShell version of
    setup-secrets.sh, for running natively from PowerShell without needing
    WSL2 or Git Bash.

.DESCRIPTION
    Same behavior as setup-secrets.sh: creates .env.local from
    local.env.example if it doesn't exist, prompts for any REPLACE_ME value,
    then renders every *.template file under this directory the same way
    render-configs.sh does (${VAR} substitution from .env.local and the
    app's own secrets.env.local, refusing an unset variable rather than
    silently substituting an empty string -- see infrastructure.md §9 on
    why envsubst's default behavior there has caused real outages
    elsewhere in this repo).

    No generate-secrets.ps1 companion: immich-ml has no secrets to
    generate, same reason setup-secrets.sh skips that step. Add one (and
    call it below) if a future app here needs it.

    Writes .env.local and any rendered file with LF line endings, not
    PowerShell's default CRLF -- a trailing \r ends up as part of the
    value when Docker Compose's --env-file parses a CRLF-terminated line,
    which is a real, silent way to break a container that looks like it
    started fine.

.NOTES
    There is no shared source between this and setup-secrets.sh -- keep
    them in sync by hand. A change to one and not the other will drift
    silently, same risk as any duplicated logic.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Dir

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-LFFile {
    # [System.IO.File]::WriteAllText, not Set-Content -- Set-Content joins
    # lines with [Environment]::NewLine, which is CRLF on Windows. See the
    # header comment above for why that matters here.
    param([string]$Path, [string[]]$Lines)
    $text = ($Lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text)
}

$EnvLocal   = Join-Path $Dir '.env.local'
$EnvExample = Join-Path $Dir 'local.env.example'

Write-Step ".env.local"

if (-not (Test-Path $EnvLocal)) {
    if (-not (Test-Path $EnvExample)) {
        throw "local.env.example not found in $Dir -- can't create .env.local from it."
    }
    Copy-Item $EnvExample $EnvLocal
    Write-Host "  created .env.local from local.env.example"
}

# NTFS has no chmod 600 equivalent worth the trouble here -- .env.local is
# already gitignored, and the closest analog (an NTFS ACL restricting the
# file to the current user) is more ceremony than every other file in this
# repo's own working copy gets. Skipped deliberately, not an oversight.

$Interactive = -not [Console]::IsInputRedirected

function Set-ReplaceMeValues {
    param([string]$Path)

    $lines = Get-Content -Path $Path
    $changed = $false
    $output = foreach ($line in $lines) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*REPLACE_ME.*)$') {
            $key = $Matches[1]
            $placeholder = $Matches[2]
            if ($Interactive) {
                $value = Read-Host "  $key (currently '$placeholder')"
            } else {
                $value = $null
            }
            if ($value) {
                $changed = $true
                "$key=$value"
            } else {
                if ($Interactive) {
                    Write-Host "  (left blank -- keeping placeholder; re-run this script once you have it)"
                }
                $line
            }
        } else {
            $line
        }
    }
    Write-LFFile -Path $Path -Lines $output
    if ($changed) { Write-Host "  updated $(Split-Path -Leaf $Path)" }
}

Set-ReplaceMeValues -Path $EnvLocal

if (Select-String -Path $EnvLocal -Pattern 'REPLACE_ME' -Quiet) {
    Write-Host "  still has a REPLACE_ME value -- re-run this script once you have it, or edit .env.local directly"
}

Write-Step "Rendering configs"

function Get-EnvMap {
    param([string]$Path)
    $map = @{}
    if (Test-Path $Path) {
        foreach ($line in Get-Content -Path $Path) {
            if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                $map[$Matches[1]] = $Matches[2].Trim("'")
            }
        }
    }
    return $map
}

$BaseEnv = Get-EnvMap -Path $EnvLocal
$Templates = Get-ChildItem -Path $Dir -Recurse -Filter '*.template' -File -ErrorAction SilentlyContinue

if (-not $Templates) {
    Write-Host "  no *.template files to render"
} else {
    $Failed = @()

    foreach ($tpl in $Templates) {
        $out = $tpl.FullName -replace '\.template$', ''
        # Not Resolve-Path -Relative: it requires the target to already
        # exist, which the rendered file doesn't yet on a first run.
        $rel = $out.Substring($Dir.Length).TrimStart('\', '/')
        $appDir = Split-Path -Parent (Split-Path -Parent $tpl.FullName)
        $secretsFile = Join-Path $appDir 'secrets.env.local'

        $localEnv = $BaseEnv.Clone()
        if (Test-Path $secretsFile) {
            (Get-EnvMap -Path $secretsFile).GetEnumerator() | ForEach-Object { $localEnv[$_.Key] = $_.Value }
        }

        $content = Get-Content -Path $tpl.FullName -Raw
        $missing = New-Object System.Collections.Generic.List[string]
        $sb = New-Object System.Text.StringBuilder
        $lastIndex = 0

        foreach ($m in [regex]::Matches($content, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}')) {
            [void]$sb.Append($content.Substring($lastIndex, $m.Index - $lastIndex))
            $name = $m.Groups[1].Value
            if ($localEnv.ContainsKey($name) -and $localEnv[$name]) {
                [void]$sb.Append($localEnv[$name])
            } else {
                [void]$missing.Add($name)
                [void]$sb.Append($m.Value)
            }
            $lastIndex = $m.Index + $m.Length
        }
        [void]$sb.Append($content.Substring($lastIndex))

        if ($missing.Count -gt 0) {
            $names = ($missing | Select-Object -Unique) -join ', '
            Write-Warning "FAILED: $rel -- unset variable(s): $names"
            $Failed += $rel
            continue
        }

        [System.IO.File]::WriteAllText($out, $sb.ToString())
        Write-Host "Rendered: $rel"
    }

    if ($Failed.Count -gt 0) {
        Write-Host ""
        Write-Host "render step: $($Failed.Count) of the templates above FAILED to render:" -ForegroundColor Red
        $Failed | ForEach-Object { Write-Host "  - $_" }
        Write-Host "Everything else rendered fine (see 'Rendered:' lines above) -- fix the failure(s) above and re-run; already-rendered files are untouched by a re-run that fixes only the broken one(s)."
        exit 1
    }
}

Write-Step "Done."
Write-Host "Next: verify GPU passthrough (README.md), then bring immich-ml up. Either:"
Write-Host "  bash .\compose.sh immich-ml up -d          # via Git Bash / WSL2"
Write-Host "  docker compose --project-directory .\immich-ml -f .\immich-ml\docker-compose.yml --env-file .\.env.local up -d   # pure PowerShell"
