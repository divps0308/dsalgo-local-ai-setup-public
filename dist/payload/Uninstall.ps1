param(
  [switch]$RemoveData,
  [switch]$RemoveModels,
  [switch]$RemoveWindowsFeatures,
  [switch]$Force,
  [switch]$Elevated
)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { } }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'Cannot determine the installed DSAlgo Local AI Setup directory.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $isPowerShellHost = [IO.Path]::GetFileName($hostExe) -match '^(powershell|pwsh)(\.exe)?$'
  $forward = @('-Elevated')
  if($RemoveData){$forward+='-RemoveData'}; if($RemoveModels){$forward+='-RemoveModels'}
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
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-DeveloperWorkbench.ps1')
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-OAuthBroker.ps1')
if(Test-DockerAvailable){
  $arguments=@('down','--remove-orphans')
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
Write-Host 'Uninstall complete. The source directory and any registered external project directories were intentionally retained.'
if($RemoveWindowsFeatures){Write-Host 'Restart Windows to finish removing installer-owned Windows features.'}
