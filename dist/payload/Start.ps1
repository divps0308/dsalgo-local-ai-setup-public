param(
  [switch]$OpenBrowser,
  [switch]$AdminPhase
)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
  try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { }
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'Cannot determine the installed DSAlgo Local AI Setup directory.' }
$commonPath = Join-Path $scriptRoot 'scripts\Common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { throw "Required lifecycle script was not found: $commonPath" }
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = $scriptRoot
function Invoke-ChildScript([string]$Name) {
  $path = Join-Path $scriptRoot $Name
  if (-not (Test-Path -LiteralPath $path)) { throw "Required lifecycle script was not found: $path" }
  $runtime = Join-Path $scriptRoot 'runtime'; New-Item -ItemType Directory -Force -Path $runtime | Out-Null
  $safe = [IO.Path]::GetFileNameWithoutExtension($Name)
  $out = Join-Path $runtime "$safe.stdout.log"; $err = Join-Path $runtime "$safe.stderr.log"
  $powershell = (Get-Command powershell.exe).Source
  & $powershell -NoProfile -ExecutionPolicy Bypass -File $path 1> $out 2> $err
  $exitCode = 0
  if($null -ne $LASTEXITCODE){$exitCode=[int]$LASTEXITCODE}
  elseif((Test-Path -LiteralPath $err) -and -not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $err -Raw))){$exitCode=1}
  if ($exitCode -ne 0) { $detail = if (Test-Path $err) { (Get-Content $err -Raw).Trim() } else { '' }; throw "$Name failed with exit code $exitCode. $detail" }
}

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
  Compose @('up','-d')
  exit 0
}

if(Test-IsAdmin){
  throw 'Start.ps1 must be launched from a normal user session so native Workbench and OAuth processes do not inherit Administrator rights.'
}
  $adminArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $scriptRoot 'Start.ps1')`"","-AdminPhase")
$process=Start-Process -FilePath (Get-Command powershell.exe).Source -Verb RunAs -ArgumentList $adminArguments -Wait -PassThru
$adminExitCode=Get-CompletedProcessExitCode $process
if($adminExitCode-ne 0){throw "Elevated service startup failed with exit code $adminExitCode."}
Invoke-ChildScript 'Start-OAuthBroker.ps1'
Invoke-ChildScript 'Start-DeveloperWorkbench.ps1'
# Give services a moment to fully bind before opening the browser.
Start-Sleep -Seconds 2
$urls = @('http://localhost:3000','http://localhost:3001',"http://localhost:$(Get-WorkbenchPort)")
foreach ($url in $urls) {
  try { Start-Process -FilePath $url } catch { Write-Warning "Could not open $url in the default browser: $($_.Exception.Message)" }
}
Write-Host 'All selected services are running. Container services were elevated; native Workbench and OAuth processes run as the current user.'
