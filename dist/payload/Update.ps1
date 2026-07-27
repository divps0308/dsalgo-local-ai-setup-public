param([switch]$SkipModels)
. "$PSScriptRoot\scripts\Common.ps1";Assert-Admin;Ensure-Env;Prepare-RuntimeSecrets
winget upgrade --id Ollama.Ollama --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
winget upgrade --id Docker.DockerDesktop --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
winget upgrade --id Python.Python.3.12 --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
if(-not$SkipModels){foreach($m in Get-ModelTags){ollama pull $m}}
Compose @('pull')
Compose @('up','-d','--build','--remove-orphans')
Write-Host 'Restart Developer Workbench from a normal non-Administrator PowerShell window to load Workbench updates.'
Write-Host 'Restart the MCP OAuth broker from a normal non-Administrator PowerShell window to load broker updates.'
