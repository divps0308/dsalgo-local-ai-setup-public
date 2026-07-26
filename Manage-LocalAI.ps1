param([ValidateSet('Install','Update','Repair','Uninstall')][string]$Action='Install',[switch]$RemoveModels,[switch]$RemoveWebUIData,[switch]$RemoveAgentWorkspace,[switch]$UninstallApplications,[switch]$ReadOnlyAgents,[switch]$WithTemporal,[switch]$WithExtendedServices)
if($ReadOnlyAgents){(Get-Content "$PSScriptRoot\.env") -replace '^AGENT_ALLOW_WRITES=.*','AGENT_ALLOW_WRITES=false'|Set-Content "$PSScriptRoot\.env"}
switch($Action){
 'Install'{& "$PSScriptRoot\Install.ps1" -WithTemporal:$WithTemporal -WithExtendedServices:$WithExtendedServices}
 'Update'{& "$PSScriptRoot\Update.ps1" -WithTemporal:$WithTemporal -WithExtendedServices:$WithExtendedServices}
 'Repair'{& "$PSScriptRoot\Repair.ps1" -WithTemporal:$WithTemporal -WithExtendedServices:$WithExtendedServices}
 'Uninstall'{& "$PSScriptRoot\Uninstall.ps1" -RemoveModels:$RemoveModels -RemoveData:$RemoveWebUIData -UninstallApplications:$UninstallApplications;if($RemoveAgentWorkspace){Remove-Item "$PSScriptRoot\workspace\*" -Recurse -Force -ErrorAction SilentlyContinue}}
}
