# setup-secrets.ps1: roastery's setup, natively from PowerShell (no WSL or Git
# Bash). The same steps as ./setup-secrets.sh on the Linux nodes: .env.local
# from local.env.example (new keys appended, renamed keys copied), a prompt
# for anything still REPLACE_ME, then render. Nothing on roastery needs a
# generated secret yet, so there's no secrets step.
. (Join-Path $PSScriptRoot '..\_lib\purrbrews.ps1')
$node = Get-Node $PSScriptRoot
Write-Step '.env.local'
Sync-EnvLocal $node
Write-Step 'Rendering configs'
if (-not (Invoke-Render $node)) { exit 1 }
Write-Step 'Done'
Write-Host 'Next: .\compose.ps1 immich-ml up -d, and .\traefik\start.ps1 for Ollama (traefik\README.md).'
