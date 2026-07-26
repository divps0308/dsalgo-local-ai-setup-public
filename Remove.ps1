param([switch]$RemoveImages,[switch]$Force)
. "$PSScriptRoot\scripts\Common.ps1"
if(-not$Force){
  $answer=Read-Host 'Remove all DS_ALGO Local AI containers and project services? Data volumes and configuration will be retained. Type REMOVE'
  if($answer-ne'REMOVE'){Write-Host 'Cancelled.';exit 1}
}
& "$PSScriptRoot\Stop-DeveloperWorkbench.ps1"
& "$PSScriptRoot\Stop-OAuthBroker.ps1"
$arguments=@('--profile','temporal','--profile','extended','down','--remove-orphans')
if($RemoveImages){$arguments+=@('--rmi','local')}
Compose $arguments
Write-Host 'Project containers and services were removed. Persistent volumes, models, and configuration were retained.'
