param(
  [switch]$WithTemporal,
  [switch]$WithExtendedServices,
  [switch]$OpenBrowser,
  [switch]$AdminPhase
)
. "$PSScriptRoot\scripts\Common.ps1"

if($AdminPhase){
  Assert-Admin
  $desktop=Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
  if(-not(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)){
    if(-not(Test-Path -LiteralPath $desktop)){throw 'Docker Desktop is not installed.'}
    Start-Process -FilePath $desktop -WindowStyle Hidden
  }
  Wait-Docker
  Ensure-Env
  Prepare-RuntimeSecrets
  $arguments=@('up','-d')
  if($WithTemporal){$arguments=@('--profile','temporal')+$arguments}
  if($WithExtendedServices){$arguments=@('--profile','extended')+$arguments}
  Compose $arguments
  exit 0
}

if(Test-IsAdmin){
  throw 'Start.ps1 must be launched from a normal user session so native Workbench and OAuth processes do not inherit Administrator rights.'
}
$adminArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"","-AdminPhase")
if($WithTemporal){$adminArguments+='-WithTemporal'}
if($WithExtendedServices){$adminArguments+='-WithExtendedServices'}
$process=Start-Process -FilePath (Get-Command powershell.exe).Source -Verb RunAs -ArgumentList $adminArguments -Wait -PassThru
if($process.ExitCode-ne 0){throw "Elevated service startup failed with exit code $($process.ExitCode)."}
& "$PSScriptRoot\Start-OAuthBroker.ps1"
& "$PSScriptRoot\Start-DeveloperWorkbench.ps1"
if($OpenBrowser){
  Start-Process 'http://localhost:3000'
  Start-Process 'http://localhost:3001'
  Start-Process "http://localhost:$(Get-WorkbenchPort)"
  if($WithTemporal){Start-Process 'http://localhost:8088'}
}
Write-Host 'All selected services are running. Container services were elevated; native Workbench and OAuth processes run as the current user.'
