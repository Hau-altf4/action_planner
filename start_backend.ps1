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

# Scheduled Tasks receive a much smaller PATH than an interactive terminal.
# Resolve Node from the usual installation locations as well, otherwise the
# Android bridge silently fails before it can create a backend log.
function Resolve-NodePath {
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  $candidates = @(
    $command.Source
    (Join-Path $env:ProgramFiles 'nodejs\node.exe')
    $(if (${env:ProgramFiles(x86)}) {
      Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'
    })
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  return $candidates | Select-Object -First 1
}

function Test-LocalPort {
  param(
    [Parameter(Mandatory = $true)]
    [int]$Port
  )

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $connection = $client.ConnectAsync('127.0.0.1', $Port)
    return $connection.Wait(500) -and $client.Connected
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

function Resolve-MongodPath {
  $command = Get-Command mongod.exe -ErrorAction SilentlyContinue
  $candidates = @()
  if ($command) {
    $candidates += $command.Source
  }

  $serverRoot = Join-Path $env:ProgramFiles 'MongoDB\Server'
  if (Test-Path -LiteralPath $serverRoot) {
    $candidates += Get-ChildItem -LiteralPath $serverRoot -Directory |
      Sort-Object Name -Descending |
      ForEach-Object { Join-Path $_.FullName 'bin\mongod.exe' }
  }

  return $candidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1
}

function Get-ConfiguredMongoUri {
  $envPath = Join-Path $backendPath '.env'
  if (-not (Test-Path -LiteralPath $envPath)) {
    return 'mongodb://127.0.0.1:27017/action_planner'
  }

  $setting = Get-Content -LiteralPath $envPath |
    Where-Object { $_ -match '^\s*MONGODB_URI\s*=' } |
    Select-Object -First 1
  if (-not $setting) {
    return 'mongodb://127.0.0.1:27017/action_planner'
  }

  return (($setting -split '=', 2)[1]).Trim().Trim('"').Trim("'")
}

function Start-LocalMongoIfNeeded {
  $mongoUri = Get-ConfiguredMongoUri
  if ($mongoUri -notmatch '^mongodb(?:\+srv)?://(?:[^/@]+@)?(?:127\.0\.0\.1|localhost)(?::27017)?(?:/|$)') {
    return
  }
  if (Test-LocalPort -Port 27017) {
    return
  }

  $mongoService = Get-Service -Name MongoDB -ErrorAction SilentlyContinue
  if ($mongoService) {
    if ($mongoService.Status -ne 'Running') {
      Start-Service -InputObject $mongoService
    }
  } else {
    $mongodPath = Resolve-MongodPath
    if (-not $mongodPath) {
      throw 'MongoDB local chưa chạy và không tìm thấy mongod.exe. Hãy cài MongoDB Community Server hoặc cấu hình MONGODB_URI từ xa.'
    }

    $mongoDataPath = Join-Path $backendPath 'data\mongodb'
    $mongoLogPath = Join-Path $logPath 'mongodb.log'
    New-Item -ItemType Directory -Path $mongoDataPath -Force | Out-Null
    Start-Process `
      -FilePath $mongodPath `
      -ArgumentList @(
        '--dbpath', $mongoDataPath,
        '--bind_ip', '127.0.0.1',
        '--port', '27017',
        '--logpath', $mongoLogPath,
        '--logappend'
      ) `
      -WindowStyle Hidden | Out-Null
  }

  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    if (Test-LocalPort -Port 27017) {
      return
    }
  }

  throw "MongoDB local không sẵn sàng sau 20 giây. Kiểm tra nhật ký: $logPath\mongodb.log"
}

New-Item -ItemType Directory -Path $logPath -Force | Out-Null

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

Start-LocalMongoIfNeeded

$nodePath = Resolve-NodePath
if (-not $nodePath) {
  $message = 'Không tìm thấy Node.js. Hãy cài Node.js 20+ hoặc thêm node.exe vào PATH.'
  Set-Content -LiteralPath $stderrLog -Value $message -Encoding utf8
  throw "$message`nNhật ký: $stderrLog"
}
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
