# compose.ps1 <app|--all> <docker compose args...>: the PowerShell twin of
# ./compose.sh, with the same env files and the same checks before `up`.
#   .\compose.ps1 immich-ml up -d
. (Join-Path $PSScriptRoot '..\_lib\purrbrews.ps1')
Invoke-Compose (Get-Node $PSScriptRoot) $args
