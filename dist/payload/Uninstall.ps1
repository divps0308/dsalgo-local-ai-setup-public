param(
  [switch]$RemoveData,
  [switch]$RemoveModels,
  [switch]$RemoveImages,
  [switch]$RemoveWindowsFeatures,
  [switch]$Force,
  [switch]$Elevated,
  [switch]$WizardChild
)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { } }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if(-not$WizardChild -and -not$Elevated){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'scripts\LifecycleWizard.ps1') -Operation Uninstall;exit $LASTEXITCODE}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'Cannot determine the installed DSAlgo Local AI Setup directory.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  # Native Workbench/OAuth processes belong to the interactive user. Stop them
  # before elevation so their user-owned PID files and process handles remain
  # available; the elevated phase then handles Docker and machine cleanup.
  foreach($nativeStop in @('Stop-DeveloperWorkbench.ps1','Stop-OAuthBroker.ps1')) {
    $nativePath=Join-Path $scriptRoot $nativeStop
    if(Test-Path -LiteralPath $nativePath){
      try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $nativePath } catch { Write-Warning "Could not stop $nativeStop before elevation: $($_.Exception.Message)" }
    }
  }
  $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $isPowerShellHost = [IO.Path]::GetFileName($hostExe) -match '^(powershell|pwsh)(\.exe)?$'
  $forward = @('-Elevated','-WizardChild')
  if($RemoveData){$forward+='-RemoveData'}; if($RemoveModels){$forward+='-RemoveModels'}; if($RemoveImages){$forward+='-RemoveImages'}
  if($RemoveWindowsFeatures){$forward+='-RemoveWindowsFeatures'}; if($Force){$forward+='-Force'}
  $arguments = if ($isPowerShellHost) { @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $scriptRoot 'Uninstall.ps1')`"") + $forward } else { $forward }
  $elevatedProcess = Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $arguments -PassThru
  $elevatedProcess.WaitForExit(); $elevatedProcess.Refresh()
  exit $elevatedProcess.ExitCode
}
$commonPath = Join-Path $scriptRoot 'scripts\Common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { throw "Required lifecycle script was not found: $commonPath" }
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = $scriptRoot
Invoke-Expression (Get-Content -LiteralPath (Join-Path $scriptRoot 'scripts\Install-State.ps1') -Raw)
Invoke-Expression (Get-Content -LiteralPath (Join-Path $scriptRoot 'scripts\Shortcuts.ps1') -Raw)
Assert-Admin
if(-not$Force){
  Write-Warning 'Uninstall removes project containers and installer-owned applications. -RemoveData also deletes local service volumes, credentials, runtime state, and personal configuration copies.'
  $answer=Read-Host 'Type UNINSTALL to continue'
  if($answer-ne'UNINSTALL'){Write-Host 'Cancelled.';exit 1}
}
$state=Get-InstallState
# Docker Compose cleanup requires a running Docker engine. Start Docker
# Desktop when it is installed but not currently running, then wait for the
# engine before attempting container/image removal.
if(Test-DockerAvailable){
  $dockerDesktop=Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'
  if(-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)){
    if(Test-Path -LiteralPath $dockerDesktop){Start-Process -FilePath $dockerDesktop -WindowStyle Hidden}
  }
  try { Wait-Docker } catch { Write-Warning "Docker Desktop was not ready; container cleanup will be skipped: $($_.Exception.Message)" }
}
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-DeveloperWorkbench.ps1')
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-OAuthBroker.ps1')
if(Test-DockerAvailable){
  $arguments=@('down','--remove-orphans')
  if($RemoveData){$arguments+='--volumes'}
  # Explicit purge removes images belonging to this Compose project. This is
  # intentionally opt-in because an image may otherwise be shared by Docker.
  if($RemoveImages){$arguments+=@('--rmi','all')}
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
    & winget uninstall --id $application[1] --exact --accept-source-agreements --disable-interactivity
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
# The installed application directory is installer-owned and must not be left
# behind. Schedule deletion in a detached process because this script may be
# running from uninstall.exe inside the directory being removed. The marker
# prevents a source checkout without an installation state from being erased.
$installStateMarker=Join-Path $Root 'runtime\install-state.json'
if(Test-Path -LiteralPath $installStateMarker){
  $targetRoot=[IO.Path]::GetFullPath($Root)
  if($targetRoot.Length -lt 4 -or $targetRoot -match '^[A-Za-z]:\\?$'){throw 'Refusing to remove an unsafe installation path.'}
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
    "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '$($targetRoot.Replace("'","''"))' -Recurse -Force -ErrorAction SilentlyContinue"
  ))
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null
  Write-Host 'Uninstall complete. The installer-owned application directory is scheduled for permanent removal.'
} else {
  Write-Host 'Uninstall complete. No installer state marker was found; the current directory was retained.'
}
if($RemoveWindowsFeatures){Write-Host 'Restart Windows to finish removing installer-owned Windows features.'}
