# purrbrews.ps1: the Windows side of _lib, for roastery. Dot-sourced by
# roastery's setup-secrets.ps1, render-configs.ps1 and compose.ps1.
#
# It mirrors the bash scripts on purpose, so roastery doesn't need WSL or Git
# Bash: the same env files in the same order, the same REPLACE_ME rules, the
# same renamed-keys list, and templates rendered the same way (a missing
# variable fails that one file and leaves the last good render alone). If you
# change the behaviour of one side, change the other; tests/test_infrastructure.py
# renders a template through both and compares.
#
# Files are written with LF endings. A CRLF .env line leaves a \r on the end
# of the value, and the container that reads it looks fine until it isn't.

$ErrorActionPreference = 'Stop'
$script:Lib = $PSScriptRoot
$script:Stacks = Split-Path -Parent $script:Lib
$script:Root = Split-Path -Parent $script:Stacks

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-LFFile([string]$Path, [string[]]$Lines) {
    $tmp = "$Path.tmp$PID"
    [System.IO.File]::WriteAllText($tmp, (($Lines -join "`n") + "`n"))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-Node([string]$NodeDir) {
    # node.conf is bash; only the APPS=(...) line matters on Windows.
    $dir = (Resolve-Path -LiteralPath $NodeDir).Path
    $conf = Join-Path $dir 'node.conf'
    if (-not (Test-Path -LiteralPath $conf)) { throw "$dir has no node.conf" }
    $apps = @()
    foreach ($line in Get-Content -LiteralPath $conf) {
        if ($line -match '^\s*APPS=\((.*)\)') { $apps = -split $Matches[1] }
    }
    $envLocal = Join-Path $dir '.env.local'
    [pscustomobject]@{
        Dir      = $dir
        Name     = Split-Path -Leaf $dir
        Apps     = $apps
        EnvLocal = $envLocal
        # Later files win, the same order as common.sh.
        EnvFiles = @((Join-Path $script:Stacks 'fleet.env'), (Join-Path $script:Root '.env'), $envLocal)
    }
}

function Read-EnvFile([string]$Path) {
    # KEY=value lines, one layer of matching quotes removed. Never executed.
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $key, $value = $Matches[1], $Matches[2]
            if ($value -match "^'(.*)'$" -or $value -match '^"(.*)"$') { $value = $Matches[1] }
            $map[$key] = $value
        }
    }
    return $map
}

function Get-EffectiveEnv($Node, [string]$App) {
    $files = @($Node.EnvFiles)
    if ($App) { $files += (Join-Path (Join-Path $Node.Dir $App) 'secrets.env.local') }
    $merged = @{}
    foreach ($file in $files) {
        $values = Read-EnvFile $file
        foreach ($key in $values.Keys) { $merged[$key] = $values[$key] }
    }
    return $merged
}

function Test-Placeholder([string]$Value) {
    return (-not $Value) -or ($Value -match 'REPLACE_ME')
}

function Sync-EnvLocal($Node) {
    # Same three steps as setup.sh: renames, new keys from the example, prompts.
    $example = Join-Path $Node.Dir 'local.env.example'
    if (-not (Test-Path -LiteralPath $Node.EnvLocal)) {
        Copy-Item -LiteralPath $example -Destination $Node.EnvLocal
        Write-Host '  created from local.env.example'
    }
    $lines = [System.Collections.Generic.List[string]]@(Get-Content -LiteralPath $Node.EnvLocal)
    $have = Read-EnvFile $Node.EnvLocal

    foreach ($line in Get-Content -LiteralPath (Join-Path $script:Lib 'renamed-keys')) {
        $f = -split $line
        if ($f.Count -lt 2 -or $f[0].StartsWith('#')) { continue }
        if ($have.Contains($f[0]) -and -not $have.Contains($f[1])) {
            $lines.Add("$($f[1])=$($have[$f[0]])")
            $have[$f[1]] = $have[$f[0]]
            Write-Host "  copied $($f[0]) to its new name $($f[1])"
        }
    }
    foreach ($line in Get-Content -LiteralPath $example) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=' -and -not $have.Contains($Matches[1])) {
            $lines.Add($line)
            Write-Host "  added new key $($Matches[1])"
        }
    }

    $interactive = -not [Console]::IsInputRedirected
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*REPLACE_ME.*)$') {
            $key = $Matches[1]
            $value = if ($interactive) { Read-Host "  $key (now '$($Matches[2])')" } else { '' }
            if ($value) { $lines[$i] = "$key=$value" } else { Write-Host "  $key still needs a value" }
        }
    }
    Write-LFFile $Node.EnvLocal $lines
}

function Get-TemplateAppDir($Node, [string]$Template) {
    # The first folder under the node, the same as render-configs.sh.
    $relative = $Template.Substring($Node.Dir.Length).TrimStart('\', '/')
    $first = ($relative -split '[\\/]')[0]
    return Join-Path $Node.Dir $first
}

function Invoke-Render($Node) {
    # ${VAR} and $VAR, like render-template.py: every variable outside comment
    # lines must be set and not REPLACE_ME, or the file isn't written at all.
    $pattern = '\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))'
    $templates = @(Get-ChildItem -LiteralPath $Node.Dir -Recurse -Filter '*.template' -File | Sort-Object FullName)
    $failed = 0
    foreach ($tpl in $templates) {
        $out = $tpl.FullName -replace '\.template$', ''
        $relative = $out.Substring($Node.Dir.Length).TrimStart('\', '/')
        $app = Split-Path -Leaf (Get-TemplateAppDir $Node $tpl.FullName)
        $values = Get-EffectiveEnv $Node $app
        $text = [System.IO.File]::ReadAllText($tpl.FullName)
        $active = ($text -split "`n" | Where-Object { -not $_.TrimStart().StartsWith('#') }) -join "`n"
        $missing = @([regex]::Matches($active, $pattern) | ForEach-Object {
            $name = if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
            if (Test-Placeholder $values[$name]) { $name }
        } | Select-Object -Unique)
        if ($missing.Count -gt 0) {
            Write-Warning "FAILED: $relative (unset, empty or placeholder: $($missing -join ', '))"
            $failed++
            continue
        }
        $rendered = [regex]::Replace($text, $pattern, {
            param($m)
            $name = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            if ($values.ContainsKey($name)) { $values[$name] } else { $m.Value }
        })
        $tmp = "$out.tmp$PID"
        [System.IO.File]::WriteAllText($tmp, $rendered)
        Move-Item -LiteralPath $tmp -Destination $out -Force
        Write-Host "Rendered: $relative"
    }
    Write-Host "render-configs: $($templates.Count) template(s), $failed failure(s)."
    return ($failed -eq 0)
}

function Find-Placeholder($Value, [string]$Path) {
    # Field paths only, never values: the resolved config holds credentials.
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Value.PSObject.Properties) { Find-Placeholder $p.Value "$Path.$($p.Name)" }
    } elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $i = 0
        foreach ($item in $Value) { Find-Placeholder $item "$Path[$i]"; $i++ }
    } elseif ($Value -is [string] -and $Value -match 'replace_me') {
        $Path
    }
}

function Invoke-Compose($Node, [string[]]$Arguments) {
    if ($Arguments.Count -lt 2) { throw 'usage: compose.ps1 <app|--all> <docker compose args...>' }
    $target = $Arguments[0]
    $rest = @($Arguments | Select-Object -Skip 1)
    $apps = if ($target -in '--all', 'all') {
        if ($rest -contains 'down' -or $rest -contains 'stop' -or $rest -contains 'rm') { $r = @($Node.Apps); [array]::Reverse($r); $r } else { $Node.Apps }
    } else { @($target) }

    foreach ($app in $apps) {
        $appDir = Join-Path $Node.Dir $app
        $composeFile = Join-Path $appDir 'docker-compose.yml'
        if (-not (Test-Path -LiteralPath $composeFile)) { throw "no such app: $app (apps: $($Node.Apps -join ' '))" }
        $composeArgs = @('compose', '--project-directory', $appDir, '-f', $composeFile)
        foreach ($f in @($Node.EnvFiles) + (Join-Path $appDir 'secrets.env.local')) {
            if (Test-Path -LiteralPath $f) { $composeArgs += @('--env-file', $f) }
        }
        $verb = $rest | Where-Object { -not $_.StartsWith('-') } | Select-Object -First 1
        if ($verb -in 'up', 'create', 'start', 'restart') {
            if (-not (Test-Path -LiteralPath $Node.EnvLocal)) { throw '.env.local is missing; run .\setup-secrets.ps1 first.' }
            foreach ($tpl in Get-ChildItem -LiteralPath $appDir -Recurse -Filter '*.template' -File) {
                $out = $tpl.FullName -replace '\.template$', ''
                if (-not (Test-Path -LiteralPath $out)) { throw "$out hasn't been rendered; run .\render-configs.ps1." }
            }
            $json = & docker @composeArgs config --format json
            if ($LASTEXITCODE -ne 0) { throw "${app}: docker compose config failed." }
            $bad = @(Find-Placeholder ($json | Out-String | ConvertFrom-Json) 'config')
            if ($bad.Count -gt 0) { throw "${app}: unfilled placeholders in $($bad -join ', '). Values withheld." }
        }
        if ($apps.Count -gt 1) { Write-Host "── $app" }
        & docker @composeArgs @rest
        if ($LASTEXITCODE -ne 0) { throw "${app}: docker compose exited with $LASTEXITCODE." }
    }
}
