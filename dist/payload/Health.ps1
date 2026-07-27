param([switch]$LoadTestModels)
. "$PSScriptRoot\scripts\Common.ps1"
Assert-Command docker
try{$policy=Get-Content -LiteralPath "$PSScriptRoot\config\runtime-policy.json" -Raw|ConvertFrom-Json;Write-Host "=== Operating mode: $($policy.mode) ==="}catch{Write-Warning "Runtime policy unavailable: $_"}
Write-Host '=== Docker services ===';Compose @('ps')
Write-Host '=== Host memory ===';Get-CimInstance Win32_OperatingSystem|Select-Object @{n='TotalGB';e={[math]::Round($_.TotalVisibleMemorySize/1MB,1)}},@{n='FreeGB';e={[math]::Round($_.FreePhysicalMemory/1MB,1)}}|Format-Table
Write-Host '=== NVIDIA GPU ==='
if(Get-Command nvidia-smi -ErrorAction SilentlyContinue){nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv,noheader; Write-Host '=== Ollama processor placement ==='; try{ollama ps}catch{Write-Warning $_}}
else{Write-Warning 'nvidia-smi not found.'}
try{$tags=Invoke-RestMethod http://localhost:11434/api/tags;Write-Host "Installed Ollama models: $($tags.models.Count)"}catch{Write-Warning "Ollama unavailable: $_"}
foreach($u in @('http://localhost:8001/health','http://localhost:3001/api/config',"http://localhost:$(Get-WorkbenchPort)/health","http://localhost:$(Get-OAuthBrokerPort)/health",'http://localhost:3000')){try{$r=Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 10;Write-Host "$u -> $($r.StatusCode)"}catch{Write-Warning "$u -> $($_.Exception.Message)"}}
if($LoadTestModels){& "$PSScriptRoot\Benchmark.ps1" -Quick}
