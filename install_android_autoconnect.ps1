$ErrorActionPreference = 'Stop'

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$watcherPath = Join-Path $projectPath 'keep_android_connected.ps1'
$taskName = 'Action Planner Android Bridge'

if (-not (Test-Path -LiteralPath $watcherPath)) {
  throw "Watcher script was not found: $watcherPath"
}

$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' +
  '"' + $watcherPath + '" -Once'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# Chạy một lần kiểm tra ngắn mỗi phút thay vì giữ một PowerShell sống mãi.
# Flutter/ADB có thể dừng tiến trình nền khi khởi động lại ADB server; lần chạy
# kế tiếp sẽ tự tạo lại adb reverse mà không cần người dùng can thiệp.
$watchdogTrigger = New-ScheduledTaskTrigger `
  -Once `
  -At (Get-Date).AddSeconds(10) `
  -RepetitionInterval (New-TimeSpan -Minutes 1) `
  -RepetitionDuration (New-TimeSpan -Days 3650)
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
Start-Sleep -Seconds 5

$task = Get-ScheduledTask -TaskName $taskName
$taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
$triggerCount = @($task.Triggers).Count
Write-Host "Installed: $taskName"
Write-Host "State: $($task.State)"
Write-Host "Last result: $($taskInfo.LastTaskResult)"
Write-Host "Triggers: $triggerCount (logon + every minute)"

if ($triggerCount -lt 2) {
  throw 'Scheduled Task was installed without the repeating watchdog trigger.'
}
