param(
  [switch]$RemoveData,
  [switch]$RemoveModels,
  [switch]$RemoveWindowsFeatures,
  [switch]$Force
)
. "$PSScriptRoot\scripts\Common.ps1"
. "$PSScriptRoot\scripts\Install-State.ps1"
. "$PSScriptRoot\scripts\Shortcuts.ps1"
Assert-Admin
if(-not$Force){
  Write-Warning 'Uninstall removes project containers and installer-owned applications. -RemoveData also deletes local service volumes, credentials, runtime state, and personal configuration copies.'
  $answer=Read-Host 'Type UNINSTALL to continue'
  if($answer-ne'UNINSTALL'){Write-Host 'Cancelled.';exit 1}
}
$state=Get-InstallState
& "$PSScriptRoot\Stop-DeveloperWorkbench.ps1"
& "$PSScriptRoot\Stop-OAuthBroker.ps1"
if(Get-Command docker -ErrorAction SilentlyContinue){
  $arguments=@('--profile','temporal','--profile','extended','down','--remove-orphans')
  if($RemoveData){$arguments+='--volumes'}
  $arguments+=@('--rmi','local')
  try{Compose $arguments}catch{Write-Warning "Container cleanup was incomplete: $_"}
}
if($RemoveModels-and(Get-Command ollama -ErrorAction SilentlyContinue)){
  foreach($model in @($state.pulledModels)){if($model){& ollama rm $model}}
}
Remove-LocalAIShortcuts

if($state.wslConfigBackup-and(Test-Path -LiteralPath $state.wslConfigBackup)){
  Copy-Item -LiteralPath $state.wslConfigBackup -Destination (Join-Path $env:USERPROFILE '.wslconfig') -Force
}
foreach($application in @(
  @('python','Python.Python.3.12'),
  @('ollama','Ollama.Ollama'),
  @('docker','Docker.DockerDesktop')
)){
  if($state.installed.($application[0])){
    & winget uninstall --id $application[1] --exact --accept-source-agreements
    if($LASTEXITCODE-ne 0){Write-Warning "Could not uninstall $($application[1])."}
  }
}
if($RemoveWindowsFeatures){
  foreach($feature in @(
    @('wslFeature','Microsoft-Windows-Subsystem-Linux'),
    @('virtualMachinePlatform','VirtualMachinePlatform')
  )){
    if($state.installed.($feature[0])){
      Disable-WindowsOptionalFeature -Online -FeatureName $feature[1] -NoRestart|Out-Null
    }
  }
}
if($RemoveData){
  $runtime=Join-Path $Root 'runtime'
  $config=Join-Path $Root 'config'
  if([IO.Path]::GetFullPath($runtime)-ne[IO.Path]::GetFullPath((Join-Path $Root 'runtime'))){throw 'Runtime path validation failed.'}
  if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force}
  foreach($name in @('.env','config\secrets.dpapi.json','config\oauth-tokens.dpapi.json')){
    Remove-Item -LiteralPath (Join-Path $Root $name) -Force -ErrorAction SilentlyContinue
  }
  Get-ChildItem -LiteralPath $config -Filter 'personal-*' -File -ErrorAction SilentlyContinue|Remove-Item -Force
}
Write-Host 'Uninstall complete. The source directory and any registered external project directories were intentionally retained.'
if($RemoveWindowsFeatures){Write-Host 'Restart Windows to finish removing installer-owned Windows features.'}
