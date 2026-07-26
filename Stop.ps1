param([switch]$RemoveRuntimeSecrets)
. "$PSScriptRoot\scripts\Common.ps1"
& "$PSScriptRoot\Stop-DeveloperWorkbench.ps1"
& "$PSScriptRoot\Stop-OAuthBroker.ps1"
if(Get-Command docker -ErrorAction SilentlyContinue){
  try{Compose @('--profile','temporal','--profile','extended','stop')}catch{Write-Warning $_}
}
if($RemoveRuntimeSecrets){
  $secret=Join-Path $Root 'runtime\secrets.json'
  Remove-Item -LiteralPath $secret -Force -ErrorAction SilentlyContinue
}
Write-Host 'Services stopped. Containers, images, volumes, and configuration were retained.'
