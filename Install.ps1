param(
  [switch]$WithTemporal,
  [switch]$WithExtendedServices,
  [switch]$SkipModels,
  [switch]$SkipWSLConfig,
  [switch]$RestartIfRequired,
  [switch]$UsePersonalConfig
)
. "$PSScriptRoot\scripts\Common.ps1"
. "$PSScriptRoot\scripts\Install-State.ps1"
. "$PSScriptRoot\scripts\Configuration.ps1"
. "$PSScriptRoot\scripts\Shortcuts.ps1"
Assert-Admin
$state=Get-InstallState

function Enable-RequiredFeature([string]$Name,[string]$OwnershipProperty) {
  $feature=Get-WindowsOptionalFeature -Online -FeatureName $Name
  if($feature.State-eq'Enabled'){return $false}
  Write-Host "Enabling Windows feature $Name"
  $result=Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart
  $state.installed.$OwnershipProperty=$true
  Save-InstallState $state
  return [bool]$result.RestartNeeded
}
function Install-WingetPackage([string]$Command,[string]$Id,[string]$OwnershipProperty,[bool]$Force=$false) {
  if((-not$Force)-and(Get-Command $Command -ErrorAction SilentlyContinue)){return}
  & winget install --id $Id --exact --accept-source-agreements --accept-package-agreements
  if($LASTEXITCODE-ne 0){throw "Installation failed for $Id"}
  $state.installed.$OwnershipProperty=$true
  Save-InstallState $state
}
function Start-DockerDesktop {
  if(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue){return}
  $path=Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
  if(-not(Test-Path -LiteralPath $path)){throw "Docker Desktop executable not found at $path"}
  Start-Process -FilePath $path -WindowStyle Hidden
}

Assert-Command winget
$restartNeeded=$false
$restartNeeded=(Enable-RequiredFeature 'Microsoft-Windows-Subsystem-Linux' 'wslFeature')-or$restartNeeded
$restartNeeded=(Enable-RequiredFeature 'VirtualMachinePlatform' 'virtualMachinePlatform')-or$restartNeeded
Complete-InstallStep $state 'windows-features'
if($restartNeeded){
  Write-Host 'Windows must restart. Progress has been saved; rerun Install.ps1 with the same options after sign-in.'
  if($RestartIfRequired){Restart-Computer}
  exit 3010
}

Assert-Command wsl.exe
& wsl.exe --install --no-distribution
if($LASTEXITCODE-ne 0){throw 'WSL installation failed. Restart Windows if requested, then rerun Install.ps1.'}
& wsl.exe --set-default-version 2
if($LASTEXITCODE-ne 0){throw 'Unable to set WSL2 as the default version.'}
Complete-InstallStep $state 'wsl'

try{$null=Get-NativePython}catch{
  Install-WingetPackage 'python.exe' 'Python.Python.3.12' 'python' $true
  $null=Get-NativePython
}
Install-WingetPackage 'ollama.exe' 'Ollama.Ollama' 'ollama'
Install-WingetPackage 'docker.exe' 'Docker.DockerDesktop' 'docker'
$dockerBin=Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
if((Test-Path -LiteralPath $dockerBin)-and($env:Path-notlike"*$dockerBin*")){$env:Path="$dockerBin;$env:Path"}
Complete-InstallStep $state 'applications'

if(-not$SkipWSLConfig){
  if(-not$state.wslConfigBackup){
    $wslConfig=Join-Path $env:USERPROFILE '.wslconfig'
    if(Test-Path -LiteralPath $wslConfig){
      $backup=Join-Path $Root 'runtime\install-backups\wslconfig.before-install'
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup)|Out-Null
      Copy-Item -LiteralPath $wslConfig -Destination $backup -Force
      $state.wslConfigBackup=$backup
      Save-InstallState $state
    }
  }
  & "$PSScriptRoot\Configure-WSL.ps1" -Profile TemporalFriendly -Force
  & wsl.exe --shutdown
  if($LASTEXITCODE-ne 0){throw 'WSL shutdown failed.'}
}
Complete-InstallStep $state 'wsl-config'

Start-DockerDesktop
Wait-Docker
if($UsePersonalConfig){Use-PersonalConfiguration}
Assert-GenericConfiguration
Ensure-Env
Prepare-RuntimeSecrets
if(-not$SkipModels){
  foreach($model in Get-ModelTags){
    & ollama pull $model
    if($LASTEXITCODE-ne 0){throw "Failed to pull $model"}
    if($model-notin@($state.pulledModels)){$state.pulledModels=@($state.pulledModels)+$model;Save-InstallState $state}
  }
}
Complete-InstallStep $state 'models'

$profiles=@()
if($WithTemporal){$profiles+=@('--profile','temporal')}
if($WithExtendedServices){$profiles+=@('--profile','extended')}
Compose ($profiles+@('build'))
Compose ($profiles+@('create','--remove-orphans'))
Install-LocalAIShortcuts
Complete-InstallStep $state 'complete'

Write-Host 'Installation is complete and services are intentionally stopped.'
Write-Host 'Use the Start desktop shortcut or run .\Start.ps1. Rerunning Install.ps1 safely resumes or repairs missing prerequisites.'
