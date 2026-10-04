param([switch]$Rebuild)

$ErrorActionPreference = 'Stop'

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$healthUrl = 'http://127.0.0.1:8080'
$webEntry = Join-Path $projectPath 'build\web\index.html'
$logPath = Join-Path $projectPath 'backend\logs'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdoutLog = Join-Path $logPath "web-$timestamp.out.log"
$stderrLog = Join-Path $logPath "web-$timestamp.err.log"

& (Join-Path $projectPath 'start_ollama.ps1')
& (Join-Path $projectPath 'start_backend.ps1')

$sourceChanged = $false
if (Test-Path -LiteralPath $webEntry) {
  $buildTime = (Get-Item -LiteralPath $webEntry).LastWriteTimeUtc
  $sourceChanged = Get-ChildItem -LiteralPath (Join-Path $projectPath 'lib') -Recurse -File |
    Where-Object { $_.LastWriteTimeUtc -gt $buildTime } |
    Select-Object -First 1
}

if ($Rebuild -or -not (Test-Path -LiteralPath $webEntry) -or $sourceChanged) {
  Write-Host 'Web build not found. Building release...'
  & flutter build web --release
  if ($LASTEXITCODE -ne 0) { throw 'Flutter Web build failed.' }
}

$alreadyRunning = $false
try {
  $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 2
  $alreadyRunning = $response.StatusCode -eq 200
} catch {
  $alreadyRunning = $false
}

if (-not $alreadyRunning) {
  New-Item -ItemType Directory -Path $logPath -Force | Out-Null
  $nodePath = (Get-Command node -ErrorAction Stop).Source
  $process = Start-Process `
    -FilePath $nodePath `
    -ArgumentList 'tool/web_server.js' `
    -WorkingDirectory $projectPath `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -PassThru

  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 300
    if ($process.HasExited) {
      $details = if (Test-Path $stderrLog) {
        (Get-Content -LiteralPath $stderrLog -Tail 30) -join [Environment]::NewLine
      } else { 'No error log was written.' }
      throw "Web server stopped (exit code $($process.ExitCode)).`n$details"
    }
    try {
      $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 2
      if ($response.StatusCode -eq 200) { break }
    } catch {}
  }
}

$defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
  Where-Object { $_.NextHop -ne '0.0.0.0' } |
  Sort-Object RouteMetric |
  Select-Object -First 1
$address = if ($defaultRoute) {
  Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $defaultRoute.InterfaceIndex |
    Where-Object { $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1 -ExpandProperty IPAddress
} else { $null }
if (-not $address) {
  $routeLine = route print -4 |
    Select-String '^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+\S+\s+(\d+\.\d+\.\d+\.\d+)\s+\d+' |
    Select-Object -First 1
  if ($routeLine) {
    $address = $routeLine.Matches[0].Groups[1].Value
  }
}

Write-Host ''
Write-Host 'Action Planner Web is ready.' -ForegroundColor Green
Write-Host 'On this PC: http://127.0.0.1:8080'
if ($address) {
  Write-Host "On iPhone:  http://$address`:8080" -ForegroundColor Cyan
} else {
  Write-Host 'Could not detect LAN IPv4. Run ipconfig and use http://<IPv4>:8080.'
}
Write-Host 'Keep this PC, backend, and iPhone on the same Wi-Fi network.'
