param([switch]$WithTemporal,[switch]$WithExtendedServices,[switch]$SkipModels)
. "$PSScriptRoot\scripts\Common.ps1";Assert-Admin;Ensure-Env;Prepare-RuntimeSecrets
winget upgrade --id Ollama.Ollama --exact --accept-source-agreements --accept-package-agreements
winget upgrade --id Docker.DockerDesktop --exact --accept-source-agreements --accept-package-agreements
winget upgrade --id Python.Python.3.12 --exact --accept-source-agreements --accept-package-agreements
if(-not$SkipModels){foreach($m in Get-ModelTags){ollama pull $m}}
$args=@('pull');if($WithTemporal){$args=@('--profile','temporal')+$args};if($WithExtendedServices){$args=@('--profile','extended')+$args};Compose $args
$args=@('up','-d','--build','--remove-orphans');if($WithTemporal){$args=@('--profile','temporal')+$args};if($WithExtendedServices){$args=@('--profile','extended')+$args};Compose $args
Write-Host 'Restart Developer Workbench from a normal non-Administrator PowerShell window to load Workbench updates.'
Write-Host 'Restart the MCP OAuth broker from a normal non-Administrator PowerShell window to load broker updates.'
