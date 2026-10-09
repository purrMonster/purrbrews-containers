# Run with powershell -NoProfile -File tests/test_compose_helpers.ps1.
# Docker is a local function below; no daemon or service is contacted.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'stacks/_lib/purrbrews.ps1')

foreach ($case in @(
    @{ Args = @('up', '-d'); Verb = 'up'; Preview = $false },
    @{ Args = @('--profile', 'stop', 'up'); Verb = 'up'; Preview = $false },
    @{ Args = @('--project-name', 'up', 'down'); Verb = 'down'; Preview = $false },
    @{ Args = @('--dry-run', 'up'); Verb = 'up'; Preview = $true }
)) {
    $actual = Get-ComposeOptions $case.Args
    if ($actual.Verb -ne $case.Verb -or $actual.Preview -ne $case.Preview) { throw 'Command parsing mismatch' }
}

# Keep test artifacts in the ignored workspace directory for inspection.
$fixture = Join-Path $repo ('graphify-out/verification/powershell-' + [guid]::NewGuid().ToString('N'))
$app = Join-Path $fixture 'demo'
New-Item -ItemType Directory -Path $app -Force | Out-Null
$envFile = Join-Path $fixture '.env.local'
$template = Join-Path $app 'config.yml.template'
$rendered = Join-Path $app 'config.yml'
Write-LFFile (Join-Path $fixture 'node.conf') @('APPS=(demo)')
Write-LFFile (Join-Path $app 'docker-compose.yml') @('services: {}')
Write-LFFile $envFile @('NODE=example')
Write-LFFile $template @('key: value')
Write-LFFile $rendered @('key: value')
$node = Get-Node $fixture
$node.EnvFiles = @($envFile)

$script:Calls = [System.Collections.Generic.List[string]]::new()
function docker {
    $script:Calls.Add(($args -join ' '))
    $global:LASTEXITCODE = 0
    if (($args -join ' ') -like '*config --format json*') { '{"services":{}}' }
}

if (@(Invoke-Compose $node @('--list')) -join ' ' -ne 'demo') { throw 'App listing mismatch' }
if (-not ((Invoke-Compose $node @('--help')) -match 'usage:')) { throw 'Missing help' }
if ($script:Calls.Count) { throw 'Help/list contacted Docker' }

(Get-Item -LiteralPath $rendered).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(-1)
$rejected = $false
try { Invoke-Compose $node @('demo', 'up') } catch {
    if ($_.Exception.Message -notlike '*is older than*') { throw }
    $rejected = $true
}
if (-not $rejected -or $script:Calls.Count) { throw 'Stale render was not rejected before Docker' }

Invoke-Compose $node @('demo', '--dry-run', 'up')
if ($script:Calls.Count -ne 1 -or $script:Calls[0] -notlike '*--dry-run up') { throw 'Preview ran preflight' }

(Get-Item -LiteralPath $rendered).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(1)
Invoke-Compose $node @('demo', '--profile', 'stop', 'up')
if ($script:Calls.Count -ne 3 -or $script:Calls[1] -notlike '*config --format json') { throw 'Startup skipped preflight' }
'PowerShell Compose regression checks passed: parsing, help/list, stale renders, preview and startup.'
