# install.ps1: runs game-mode.ps1 at every logon, as a scheduled task.
# From an elevated PowerShell (Windows wants admin for a logon trigger):
#   .\install.ps1              install, or update after a pull, and start it
#   .\install.ps1 -Uninstall   stop it and remove the task
#
# The task runs as you, not elevated: a game runs as you, and only your own
# processes' paths are readable without admin, which is exactly the set to
# look at. No time limit: Windows' default of 3 days is what stopped
# Traefik's task on 2026-10-03 (runbook, 2026-10-04).
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$TaskName = 'purrbrews-game-mode'

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($Uninstall) {
    if (-not $existing) { Write-Host "No task named $TaskName."; exit 0 }
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed $TaskName. llama-swap keeps whatever profile it had; a restart"
    Write-Host 'of the llama-swap container puts it back to normal.'
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this from an elevated PowerShell (Run as administrator).' }

$script = Join-Path $PSScriptRoot 'game-mode.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "Missing $script" }
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name

# -WindowStyle Hidden: no console window on the desktop (it may flash once at logon).
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $PSScriptRoot `
    -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $script)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

if ($existing) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Force `
    -Description 'purrBrews: llama-swap to its CPU-only profile while a game runs (stacks\roastery\game-mode).' | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 3

$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "Task:        $TaskName ($($task.State)), runs as $user at logon"
Write-Host "Time limit:  $($task.Settings.ExecutionTimeLimit) (PT0S = none)"
Write-Host "Last result: $($info.LastTaskResult) (267009 = running)"
Write-Host "Log:         $(Join-Path $PSScriptRoot 'game-mode.log')"
Write-Host ''
Write-Host 'Check it: .\game-mode.ps1 -Once, then start a game and watch the log.'
