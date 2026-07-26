param([switch]$WithTemporal,[switch]$WithExtendedServices)
. "$PSScriptRoot\scripts\Common.ps1"
. "$PSScriptRoot\scripts\Configuration.ps1"
. "$PSScriptRoot\scripts\Shortcuts.ps1"
Assert-Admin
Wait-Docker
& "$PSScriptRoot\Stop-DeveloperWorkbench.ps1"
& "$PSScriptRoot\Stop-OAuthBroker.ps1"
$profiles=@()
if($WithTemporal){$profiles+=@('--profile','temporal')}
if($WithExtendedServices){$profiles+=@('--profile','extended')}
Compose (@('--profile','temporal','--profile','extended','down','--remove-orphans'))
Assert-GenericConfiguration
Ensure-Env
Prepare-RuntimeSecrets
Compose ($profiles+@('build'))
Compose ($profiles+@('create','--remove-orphans'))
Install-LocalAIShortcuts
Write-Host 'Repair complete. Images were rebuilt and containers recreated in the stopped state. Run .\Start.ps1 when ready.'
