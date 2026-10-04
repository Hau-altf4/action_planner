$ErrorActionPreference = 'Stop'

$healthUrl = 'http://127.0.0.1:11434/api/tags'
$model = 'qwen3:1.7b'
$envPath = Join-Path $PSScriptRoot 'backend\.env'
if (Test-Path -LiteralPath $envPath) {
  $modelLine = Get-Content -LiteralPath $envPath |
    Where-Object { $_ -match '^OLLAMA_MODEL=' } |
    Select-Object -Last 1
  if ($modelLine) { $model = ($modelLine -split '=', 2)[1].Trim() }
}

function Initialize-OllamaModel {
  param([string]$ModelName)
  try {
    $running = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 2
    if ($running.models.name -contains $ModelName) { return }
  } catch {}
  Write-Host "Warming Ollama model $ModelName..."
  $body = @{
    model = $ModelName
    stream = $false
    think = $false
    keep_alive = '2h'
    messages = @(@{ role = 'user'; content = 'Trả lời OK' })
    options = @{ num_predict = 2; num_ctx = 1024 }
  } | ConvertTo-Json -Depth 6
  $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/chat' `
    -Method POST -ContentType 'application/json' -Body $body -TimeoutSec 120
}

try {
  $null = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
  Initialize-OllamaModel -ModelName $model
  Write-Host 'Ollama is already running.'
  exit 0
} catch {}

$candidates = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
  (Join-Path $env:LOCALAPPDATA 'Ollama\ollama.exe'),
  'C:\Program Files\Ollama\ollama.exe'
)
$ollamaPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1
if (-not $ollamaPath) {
  throw 'Ollama is not installed. Download it from https://ollama.com/download/windows.'
}

$process = Start-Process -FilePath $ollamaPath -ArgumentList 'serve' `
  -WindowStyle Hidden -PassThru
for ($attempt = 0; $attempt -lt 60; $attempt++) {
  Start-Sleep -Milliseconds 500
  if ($process.HasExited) {
    throw "Ollama stopped during startup (exit code $($process.ExitCode))."
  }
  try {
    $result = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    Initialize-OllamaModel -ModelName $model
    Write-Host "Ollama started (PID $($process.Id)); models: $((($result.models).name) -join ', ')"
    exit 0
  } catch {}
}
throw 'Ollama did not become ready after 30 seconds.'
