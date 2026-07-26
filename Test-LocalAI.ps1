#requires -Version 5.1
[CmdletBinding()]
param([switch]$RunAgentSmokeTest)
. "$PSScriptRoot\scripts\Common.ps1";Ensure-Env
$envMap=@{};Get-Content "$Root\.env"|Where-Object{$_ -match '=' -and $_ -notmatch '^#'}|ForEach-Object{$k,$v=$_.Split('=',2);$envMap[$k]=$v}
$headers=@{Authorization="Bearer $($envMap.AGENT_API_KEY)"}
Write-Host 'Checking Ollama...' -ForegroundColor Cyan
$tags=Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 10;$required=Get-ModelTags;$installed=@($tags.models.name)
foreach($m in $required){if($installed -notcontains $m){throw "Missing model: $m"};Write-Host "  OK $m" -ForegroundColor Green}
Write-Host 'Checking gateway and UI...' -ForegroundColor Cyan
$health=Invoke-RestMethod http://localhost:8001/health -TimeoutSec 10;$models=Invoke-RestMethod http://localhost:8001/v1/models -Headers $headers -TimeoutSec 10
Write-Host "  OK gateway $($health.version); profiles: $((@($models.data).id)-join', ')" -ForegroundColor Green
Invoke-WebRequest http://localhost:3000 -UseBasicParsing -TimeoutSec 15|Out-Null
if($RunAgentSmokeTest){$body=@{model='agent-general';messages=@(@{role='user';content='Use the calculator tool to compute 17 * 23. Return only the result.'});stream=$false}|ConvertTo-Json -Depth 6;$r=Invoke-RestMethod -Method Post -Uri http://localhost:8001/v1/chat/completions -Headers $headers -ContentType application/json -Body $body -TimeoutSec 900;Write-Host "Response: $($r.choices[0].message.content)"}
Write-Host 'All requested checks passed.' -ForegroundColor Green
