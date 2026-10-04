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
    Write-Host 'Action Planner backend is already running.'
    exit 0
  }
} catch {
  # The backend is not listening yet, so start it below.
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
      'Node did not write an error log.'
    }
    throw "Backend stopped during startup (exit code $($process.ExitCode)).`n$details"
  }
  try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    if ($health.status -eq 'ok') {
      Write-Host "Action Planner backend started (PID $($process.Id))."
      Write-Host "MongoDB: $($health.database); AI: $($health.aiModel)"
      exit 0
    }
  } catch {
    # Give Node and MongoDB a little more time to initialize.
  }
}

throw "Backend did not become ready after 60 seconds. Check logs:`n$stdoutLog`n$stderrLog"
