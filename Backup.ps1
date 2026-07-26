param([string]$Destination="$PSScriptRoot\backups")
. "$PSScriptRoot\scripts\Common.ps1";New-Item -ItemType Directory -Force $Destination|Out-Null;$target=Join-Path $Destination "local-ai-$(Get-Date -Format yyyyMMdd-HHmmss)";New-Item -ItemType Directory $target|Out-Null
Copy-Item "$Root\config\agents.json","$Root\config\models.json","$Root\config\projects.json","$Root\config\runtime-policy.json","$Root\.env.example" $target
Copy-Item "$Root\workspace" (Join-Path $target 'workspace') -Recurse
$vol='alienware-local-ai_open-webui-data';docker run --rm -v "${vol}:/source:ro" -v "${target}:/backup" alpine sh -c 'cd /source && tar czf /backup/open-webui-data.tgz .'
Write-Host "Backup created: $target";Write-Host 'Secrets and .env are intentionally excluded. Store config/secrets.dpapi.json separately only if you accept user-bound encrypted backups.'
