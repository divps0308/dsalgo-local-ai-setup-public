param([switch]$Quick,[string]$OutputPath="$PSScriptRoot\benchmark-results.json")
. "$PSScriptRoot\scripts\Common.ps1"

function Get-VramUsedMB {
 if(-not(Get-Command nvidia-smi -ErrorAction SilentlyContinue)){return $null}
 $value=nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits|Select-Object -First 1
 if($LASTEXITCODE-ne 0 -or $null-eq$value){return $null}
 return [int]$value.Trim()
}

function Stop-OllamaModel([string]$Model) {
 $body=@{model=$Model;keep_alive=0}|ConvertTo-Json
 Invoke-RestMethod http://localhost:11434/api/generate -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120|Out-Null
}

function Get-OllamaPlacement([string]$Model) {
 $lines=@(ollama ps)
 if($LASTEXITCODE-ne 0){return $null}
 $modelLine=$lines|Where-Object{$_ -match "^\s*$([regex]::Escape($Model))\s+"}|Select-Object -First 1
 if($null-eq$modelLine){return $null}
 return $modelLine.Trim()
}

$r=Get-Registry;$results=@();$roles=@('general','coder','reasoning')
foreach($role in $roles){$cfg=$r.models.$role;$model=$cfg.ollamaTag;Write-Host "Benchmarking $role : $model"
 Stop-OllamaModel $model
 try {
  $before=Get-VramUsedMB
  $prompt=if($Quick){'Reply with exactly: benchmark ok'}elseif($role-eq'coder'){'Write a concise Python function that validates an ISO-8601 timestamp and explain two edge cases.'}elseif($role-eq'reasoning'){'Solve: A service handles 125 tasks/second. How long for 5,000,000 tasks? Show the calculation.'}else{'Summarize three practical benefits of durable workflow execution.'}
  $body=@{model=$model;stream=$false;keep_alive=$cfg.keepAlive;messages=@(@{role='user';content=$prompt});options=@{num_ctx=[int]$cfg.numCtx;temperature=[double]$cfg.temperature}}|ConvertTo-Json -Depth 8
  $sw=[Diagnostics.Stopwatch]::StartNew();$resp=Invoke-RestMethod http://localhost:11434/api/chat -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 1800;$sw.Stop()
  $after=Get-VramUsedMB
  $evalCount=[double]($resp.eval_count);$evalSec=[double]($resp.eval_duration)/1e9;$tps=if($evalSec-gt 0){[math]::Round($evalCount/$evalSec,2)}else{0}
  $placement=Get-OllamaPlacement $model
  $cpuOffload=($null-ne$placement) -and ($placement -match '(?i)CPU') -and -not($placement -match '100% GPU')
  $results += [pscustomobject]@{timestamp=(Get-Date).ToString('o');role=$role;model=$model;numCtx=$cfg.numCtx;elapsedSeconds=[math]::Round($sw.Elapsed.TotalSeconds,2);tokensPerSecond=$tps;vramBeforeMB=$before;vramAfterMB=$after;processorPlacement=$placement;cpuOffloadSuspected=$cpuOffload}
 } finally {
  Stop-OllamaModel $model
 }
}
$results|ConvertTo-Json -Depth 5|Set-Content $OutputPath -Encoding UTF8;$results|Format-Table -AutoSize;Write-Host "Saved $OutputPath"
