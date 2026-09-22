param([string]$TraefikExe = (Join-Path $PSScriptRoot 'traefik.exe'))
$ErrorActionPreference = 'Stop'
$binary = (Resolve-Path -LiteralPath $TraefikExe).Path
foreach ($relative in @('config/traefik.yml', 'config/dynamic/ollama.yml')) {
    $path = Join-Path $PSScriptRoot $relative
    if (!(Test-Path -LiteralPath $path)) { throw "Missing $relative. Run roastery/setup-secrets.ps1 first." }
    if ((Get-Content -LiteralPath $path -Raw) -match 'REPLACE_ME|\$\{') {
        throw "Unresolved settings in $relative. Complete .env.local and render again."
    }
}
if (!$env:CF_DNS_API_TOKEN -and !$env:CF_DNS_API_TOKEN_FILE) {
    throw 'Set CF_DNS_API_TOKEN or CF_DNS_API_TOKEN_FILE in this process before starting Traefik.'
}
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'data') | Out-Null
Push-Location $PSScriptRoot
try {
    & $binary '--configFile=./config/traefik.yml'
    if ($LASTEXITCODE -ne 0) { throw "Traefik exited with code $LASTEXITCODE" }
} finally {
    Pop-Location
}
