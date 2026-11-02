param(
  [switch]$Restart
)

$ErrorActionPreference = 'Stop'

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendPath = Join-Path $projectPath 'backend'
$healthUrl = 'http://127.0.0.1:3000/health'
$logPath = Join-Path $backendPath 'logs'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutLog = Join-Path $logPath "backend-$timestamp.out.log"
$stderrLog = Join-Path $logPath "backend-$timestamp.err.log"

try {
  $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
  if ($health.status -eq 'ok') {
    if (-not $Restart) {
      Write-Host 'Máy chủ Action Planner đang chạy.'
      exit 0
    }
    $connection = Get-NetTCPConnection -LocalPort 3000 -State Listen |
      Select-Object -First 1
    $backendProcess = Get-Process -Id $connection.OwningProcess
    if ($backendProcess.ProcessName -ne 'node') {
      throw "Cổng 3000 đang được dùng bởi $($backendProcess.ProcessName); không tự dừng tiến trình này."
    }
    Stop-Process -Id $backendProcess.Id
    $null = $backendProcess.WaitForExit(5000)
    Write-Host "Đã dừng máy chủ cũ (PID $($backendProcess.Id))."
  }
} catch {
  if ($_.Exception.Message -like 'Cổng 3000 đang được dùng*') {
    throw
  }
  # Máy chủ chưa hoạt động nên sẽ được khởi động bên dưới.
}

$nodePath = (Get-Command node -ErrorAction Stop).Source
New-Item -ItemType Directory -Path $logPath -Force | Out-Null
$process = Start-Process `
  -FilePath $nodePath `
  -ArgumentList 'src/server.js' `
  -WorkingDirectory $backendPath `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdoutLog `
  -RedirectStandardError $stderrLog `
  -PassThru

for ($attempt = 0; $attempt -lt 120; $attempt++) {
  Start-Sleep -Milliseconds 500
  if ($process.HasExited) {
    $details = if (Test-Path $stderrLog) {
      (Get-Content -LiteralPath $stderrLog -Tail 30) -join [Environment]::NewLine
    } else {
      'Node không ghi nhật ký lỗi.'
    }
    throw "Máy chủ dừng khi khởi động (mã $($process.ExitCode)).`n$details"
  }
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    if ($health.status -eq 'ok') {
      Write-Host "Máy chủ Action Planner đã khởi động (PID $($process.Id))."
      Write-Host "MongoDB: $($health.database); AI: $($health.aiModel); giọng nói: $($health.voice)"
      exit 0
    }
  } catch {
    # Chờ Node và MongoDB khởi động hoàn tất.
  }
}

throw "Máy chủ chưa sẵn sàng sau 60 giây. Kiểm tra nhật ký:`n$stdoutLog`n$stderrLog"
