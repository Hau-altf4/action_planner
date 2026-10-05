param(
  [int]$Port = 3000,
  [int]$PollSeconds = 2,
  [switch]$Once
)

$ErrorActionPreference = 'Continue'

$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$backendHealthUrl = "http://127.0.0.1:$Port/health"
$ollamaHealthUrl = 'http://127.0.0.1:11434/api/tags'
$logDirectory = Join-Path $projectPath 'backend\logs'
$logPath = Join-Path $logDirectory 'android-device-bridge.log'
$lastServiceCheck = [datetime]::MinValue
$knownConnectedDevices = @{}
$serviceStartAttempts = @{}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

function Write-BridgeLog {
  param([string]$Message)
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
  Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
}

function Test-HttpEndpoint {
  param([string]$Uri)
  try {
    $null = Invoke-RestMethod -Uri $Uri -TimeoutSec 2
    return $true
  } catch {
    return $false
  }
}

function Start-ProjectService {
  param([string]$ScriptName)
  $scriptPath = Join-Path $projectPath $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-BridgeLog "Missing service script: $scriptPath"
    return
  }

  $lastAttempt = $serviceStartAttempts[$ScriptName]
  if ($lastAttempt -and ((Get-Date) - $lastAttempt).TotalSeconds -lt 60) {
    return
  }

  try {
    $serviceStartAttempts[$ScriptName] = Get-Date
    Start-Process `
      -FilePath 'powershell.exe' `
      -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $scriptPath
      ) `
      -WindowStyle Hidden | Out-Null
    Write-BridgeLog "Launched $ScriptName."
  } catch {
    Write-BridgeLog "$ScriptName failed: $($_.Exception.Message)"
  }
}

function Ensure-ProjectServices {
  if (-not (Test-HttpEndpoint -Uri $backendHealthUrl)) {
    Write-BridgeLog 'Backend is unavailable; starting it.'
    Start-ProjectService -ScriptName 'start_backend.ps1'
  }

  if (-not (Test-HttpEndpoint -Uri $ollamaHealthUrl)) {
    Write-BridgeLog 'Ollama is unavailable; starting it.'
    Start-ProjectService -ScriptName 'start_ollama.ps1'
  }
}

if (-not (Test-Path -LiteralPath $adbPath)) {
  Write-BridgeLog "ADB was not found: $adbPath"
  exit 1
}

function Invoke-BridgeCheck {
  try {
    $deviceLines = & $adbPath devices 2>$null |
      Select-Object -Skip 1 |
      Where-Object { $_ -match '^([^\s]+)\s+device$' }
    $connectedSerials = @($deviceLines | ForEach-Object {
      if ($_ -match '^([^\s]+)\s+device$') { $Matches[1] }
    })

    foreach ($serial in $connectedSerials) {
      $rules = & $adbPath -s $serial reverse --list 2>$null
      if ($rules -notmatch "tcp:$Port\s+tcp:$Port") {
        $result = & $adbPath -s $serial reverse "tcp:$Port" "tcp:$Port" 2>&1
        if ($LASTEXITCODE -eq 0) {
          Write-BridgeLog "Configured ${serial}: tcp:$Port -> tcp:$Port."
        } else {
          Write-BridgeLog "Could not configure ${serial}: $result"
        }
      }

      if (-not $Once -and -not $knownConnectedDevices.ContainsKey($serial)) {
        Write-BridgeLog "Device connected: $serial."
        $knownConnectedDevices[$serial] = $true
      }
    }

    if (-not $Once) {
      foreach ($serial in @($knownConnectedDevices.Keys)) {
        if ($connectedSerials -notcontains $serial) {
          Write-BridgeLog "Device disconnected: $serial."
          $knownConnectedDevices.Remove($serial)
        }
      }
    }

    if (((Get-Date) - $lastServiceCheck).TotalSeconds -ge 15) {
      Ensure-ProjectServices
      $lastServiceCheck = Get-Date
    }
  } catch {
    Write-BridgeLog "Watcher error: $($_.Exception.Message)"
  }
}

if ($Once) {
  Invoke-BridgeCheck
  exit 0
}

Write-BridgeLog "Android bridge watcher started for tcp:$Port."

while ($true) {
  Invoke-BridgeCheck

  Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
}
