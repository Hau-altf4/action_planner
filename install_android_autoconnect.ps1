$ErrorActionPreference = 'Stop'

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcherPath = Join-Path $projectPath 'keep_android_connected.ps1'
$taskName = 'Action Planner Android Bridge'

if (-not (Test-Path -LiteralPath $watcherPath)) {
  throw "Watcher script was not found: $watcherPath"
}

$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' +
  '"' + $watcherPath + '"'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# ADB/Flutter can occasionally terminate the hidden watcher while restarting its
# server. The repeating trigger acts as a watchdog: IgnoreNew keeps the current
# watcher when it is healthy and starts a replacement within one minute when it
# has exited.
$watchdogTrigger = New-ScheduledTaskTrigger `
  -Once `
  -At (Get-Date).AddMinutes(1) `
  -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -MultipleInstances IgnoreNew

Register-ScheduledTask `
  -TaskName $taskName `
  -Action $action `
  -Trigger @($logonTrigger, $watchdogTrigger) `
  -Settings $settings `
  -Description 'Keeps Action Planner backend, Ollama, and ADB reverse port 3000 ready for Android development.' `
  -Force | Out-Null

Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3

$task = Get-ScheduledTask -TaskName $taskName
$taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
Write-Host "Installed: $taskName"
Write-Host "State: $($task.State)"
Write-Host "Last result: $($taskInfo.LastTaskResult)"
