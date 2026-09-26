# start.ps1: runs the native Traefik in the foreground. It reads its Cloudflare
# token from secrets.env.local beside this script (parsed, never executed) and
# refuses to start while a rendered config is missing or still has ${...} in it.
param(
    [string]$TraefikExe = (Join-Path $PSScriptRoot 'traefik.exe'),
    [string]$EnvFile = (Join-Path $PSScriptRoot 'secrets.env.local')
)
$ErrorActionPreference = 'Stop'

# Parse dotenv data; never dot-source or execute its contents.
function Read-TraefikEnv {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Missing Traefik environment file. Copy secrets.env.example to secrets.env.local and fill it in.'
    }
    $values = @{}
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        $entry = $line.Trim()
        if (!$entry -or $entry.StartsWith('#')) { continue }
        if ($entry -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
            throw "Invalid environment assignment at line $lineNumber. Expected NAME=value."
        }
        $name = $Matches[1]
        $value = $Matches[2].Trim()
        if ($value.StartsWith('"') -or $value.StartsWith("'")) {
            if ($value.Length -lt 2 -or $value[-1] -ne $value[0]) {
                throw "Unmatched quote at environment line $lineNumber."
            }
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($value -match 'REPLACE_ME') {
            throw "Fill in $name in the Traefik environment file before starting."
        }
        $values[$name] = $value
    }
    return $values
}

$settings = Read-TraefikEnv -Path $EnvFile
foreach ($name in $settings.Keys) {
    [Environment]::SetEnvironmentVariable($name, $settings[$name], 'Process')
}
$binary = (Resolve-Path -LiteralPath $TraefikExe).Path
foreach ($relative in @('config/traefik.yml', 'config/dynamic/ollama.yml')) {
    $path = Join-Path $PSScriptRoot $relative
    if (!(Test-Path -LiteralPath $path)) { throw "Missing $relative. Run roastery/setup-secrets.ps1 first." }
    if ((Get-Content -LiteralPath $path -Raw) -match 'REPLACE_ME|\$\{') {
        throw "Unresolved settings in $relative. Complete .env.local and render again."
    }
}
if (!$env:CF_DNS_API_TOKEN -and !$env:CF_DNS_API_TOKEN_FILE) {
    throw 'Set CF_DNS_API_TOKEN or CF_DNS_API_TOKEN_FILE in the Traefik environment file.'
}
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'data') | Out-Null
Push-Location $PSScriptRoot
try {
    & $binary '--configFile=./config/traefik.yml'
    if ($LASTEXITCODE -ne 0) { throw "Traefik exited with code $LASTEXITCODE" }
} finally {
    Pop-Location
}
