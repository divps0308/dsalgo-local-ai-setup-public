param(
  [switch]$SkipModels,
  [string[]]$SelectedModelTags,
  [switch]$SkipWSLConfig,
  [switch]$RestartIfRequired,
  [switch]$UsePersonalConfig
)
. "$PSScriptRoot\scripts\Common.ps1"
. "$PSScriptRoot\scripts\Install-State.ps1"
. "$PSScriptRoot\scripts\Configuration.ps1"
. "$PSScriptRoot\scripts\Shortcuts.ps1"
. "$PSScriptRoot\scripts\Prerequisites.ps1"
$script:PrerequisiteLogPath = Join-Path $Root 'runtime\prerequisites.log'
if(-not$SelectedModelTags){
  $selectionFile=Join-Path $PSScriptRoot 'config\selected-models.json'
  if(Test-Path -LiteralPath $selectionFile){$SelectedModelTags=@((Get-Content -LiteralPath $selectionFile -Raw|ConvertFrom-Json).tags)}
}
Assert-Admin
$state=Get-InstallState
$installLog=Join-Path $Root 'runtime\install-phases.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installLog)|Out-Null
# Installation runs elevated, but native lifecycle processes run as the
# signed-in user. Grant that user modify access to generated runtime state.
$runtimeDirectory=Split-Path -Parent $installLog
$runtimeAcl=Get-Acl -LiteralPath $runtimeDirectory
# The installer runs elevated, so $env:USERNAME may be Administrator. Resolve
# the interactive desktop account so native Workbench/OAuth processes can
# write runtime state without running elevated.
$interactiveUser=(Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
if([string]::IsNullOrWhiteSpace($interactiveUser)){$interactiveUser="$env:USERDOMAIN\$env:USERNAME"}
$runtimeUser=New-Object Security.Principal.NTAccount($interactiveUser)
$runtimeRule=New-Object Security.AccessControl.FileSystemAccessRule($runtimeUser,'Modify','ContainerInherit,ObjectInherit','None','Allow')
$runtimeAcl.SetAccessRule($runtimeRule)
Set-Acl -LiteralPath $runtimeDirectory -AclObject $runtimeAcl
function Write-InstallPhase([string]$Name){Write-Host "Phase: $Name";"$(Get-Date -Format s) $Name"|Add-Content -LiteralPath $installLog -Encoding UTF8}
Write-InstallPhase 'installer-started'

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
  $wingetLog=Join-Path ([IO.Path]::GetTempPath()) "dsalgo-winget-$Id.log"
  & winget install --id $Id --exact --accept-source-agreements --accept-package-agreements --disable-interactivity 1> $wingetLog 2>&1
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
function Wait-Ollama([int]$Seconds=60) {
  $end=(Get-Date).AddSeconds($Seconds)
  do { try { $r=Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 3;if($r.StatusCode-eq 200){return} } catch {}; Start-Sleep -Seconds 2 } while((Get-Date)-lt$end)
  throw 'Ollama did not become ready on http://127.0.0.1:11434.'
}
function Start-OllamaIfNeeded {
  try { $r=Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 3;if($r.StatusCode-eq 200){return} } catch {}
  $ollama=(Get-Command ollama.exe -ErrorAction Stop).Source
  Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
  Wait-Ollama
}
function Pull-OllamaModel([string]$Model) {
  $safe=$Model -replace '[^A-Za-z0-9._-]','-'
  $out=Join-Path $Root "runtime\ollama-pull-$safe.out.log"
  $err=Join-Path $Root "runtime\ollama-pull-$safe.err.log"
  $ollama=(Get-Command ollama.exe -ErrorAction Stop).Source
  Write-Host "Downloading model: $Model"
  $p=Start-Process -FilePath $ollama -ArgumentList @('pull',$Model) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  if($p.ExitCode-ne 0){throw "Ollama could not download $Model (exit $($p.ExitCode)). See $out and $err."}
  Write-Host "Downloaded model: $Model"
}

$restartNeeded=$false
Write-InstallPhase 'windows-features'
$restartNeeded=(Enable-RequiredFeature 'Microsoft-Windows-Subsystem-Linux' 'wslFeature')-or$restartNeeded
$restartNeeded=(Enable-RequiredFeature 'VirtualMachinePlatform' 'virtualMachinePlatform')-or$restartNeeded
Complete-InstallStep $state 'windows-features'
if($restartNeeded){
  Write-Host 'Windows must restart. Progress has been saved; rerun Install.exe with the same options after sign-in.'
  if($RestartIfRequired){Restart-Computer}
  exit 3010
}

# Enabling the WSL and Virtual Machine Platform Windows features is sufficient
# here. Docker Desktop configures its own WSL2 backend. Avoid invoking the
# Store-delivered WSL client during installation because it can perform an
# online manifest lookup even when no distribution is requested.
Complete-InstallStep $state 'wsl'
Write-InstallPhase 'applications'

try{$null=Get-NativePython}catch{
  Ensure-Prerequisite 'Python' 'python.exe' 'Python.Python.3.12' 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' @('/quiet','InstallAllUsers=0','PrependPath=1')
  $null=Get-NativePython
}
Ensure-Prerequisite 'Ollama' 'ollama.exe' 'Ollama.Ollama' 'https://ollama.com/download/OllamaSetup.exe' @('/SILENT')
Ensure-Prerequisite 'Docker Desktop' 'docker.exe' 'Docker.DockerDesktop' 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe' @('install','--quiet')
$dockerBin=Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
if((Test-Path -LiteralPath $dockerBin)-and($env:Path-notlike"*$dockerBin*")){$env:Path="$dockerBin;$env:Path"}
Complete-InstallStep $state 'applications'
Write-InstallPhase 'wsl-config'

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
  & "$PSScriptRoot\Configure-WSL.ps1" -Profile Core
  Write-Host 'Updating the WSL kernel and client'
  & wsl.exe --update --web-download
  if($LASTEXITCODE-ne 0){throw 'WSL update failed. Run "wsl.exe --update --web-download" as Administrator, then rerun Install.exe.'}
  & wsl.exe --shutdown
  if($LASTEXITCODE-ne 0){throw 'WSL shutdown failed.'}
}
Complete-InstallStep $state 'wsl-config'

Write-InstallPhase 'docker-and-models'
Start-DockerDesktop
Wait-Docker
if($UsePersonalConfig){Use-PersonalConfiguration}
Assert-GenericConfiguration
Ensure-Env
Prepare-RuntimeSecrets
if(-not$SkipModels){
  Start-OllamaIfNeeded
  $modelsToPull = if($SelectedModelTags -and @($SelectedModelTags).Count -gt 0){ @($SelectedModelTags) } else { @(Get-ModelTags) }
  foreach($model in $modelsToPull){
    Pull-OllamaModel $model
    if($model-notin@($state.pulledModels)){$state.pulledModels=@($state.pulledModels)+$model;Save-InstallState $state}
  }
}
Complete-InstallStep $state 'models'

Write-InstallPhase 'compose'
Compose @('build')
Compose @('create','--remove-orphans')
Install-LocalAIShortcuts
Register-DSAlgoUninstall
Complete-InstallStep $state 'complete'
Write-InstallPhase 'complete'

Write-Host 'Installation is complete and services are intentionally stopped.'
Write-Host 'Use the Start desktop shortcut or run .\Start.ps1. Rerunning Install.ps1 safely resumes or repairs missing prerequisites.'
