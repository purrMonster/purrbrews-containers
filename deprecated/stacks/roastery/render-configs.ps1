# render-configs.ps1: every *.template under roastery, rendered next to itself.
# The PowerShell twin of ./render-configs.sh; the logic is in ..\_lib\purrbrews.ps1.
. (Join-Path $PSScriptRoot '..\_lib\purrbrews.ps1')
if (-not (Invoke-Render (Get-Node $PSScriptRoot))) { exit 1 }
