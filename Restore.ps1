param([Parameter(Mandatory)][string]$Source)
. "$PSScriptRoot\scripts\Common.ps1";if(-not(Test-Path $Source)){throw 'Backup path not found'};& "$PSScriptRoot\Stop-DeveloperWorkbench.ps1";& "$PSScriptRoot\Stop-OAuthBroker.ps1";Compose @('down')
Copy-Item "$Source\agents.json" "$Root\config\agents.json" -Force;Copy-Item "$Source\models.json" "$Root\config\models.json" -Force
if(Test-Path "$Source\runtime-policy.json"){Copy-Item "$Source\runtime-policy.json" "$Root\config\runtime-policy.json" -Force}
if(Test-Path "$Source\projects.json"){Copy-Item "$Source\projects.json" "$Root\config\projects.json" -Force}
if(Test-Path "$Source\workspace"){Copy-Item "$Source\workspace\*" "$Root\workspace" -Recurse -Force}
if(Test-Path "$Source\open-webui-data.tgz"){docker run --rm -v 'alienware-local-ai_open-webui-data:/target' -v "${Source}:/backup:ro" alpine sh -c 'rm -rf /target/* && tar xzf /backup/open-webui-data.tgz -C /target'}
Write-Host 'Restore complete. Run Start.ps1.'
