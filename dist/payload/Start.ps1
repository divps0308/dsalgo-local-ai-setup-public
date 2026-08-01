param(
  [switch]$OpenBrowser,
  [switch]$AdminPhase,
  [switch]$WizardChild
)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
  try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { }
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if(-not$WizardChild -and -not$AdminPhase){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'scripts\LifecycleWizard.ps1') -Operation Start;exit $LASTEXITCODE}
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
  $child=Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$path`"") -WorkingDirectory $scriptRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
  $deadline=(Get-Date).AddSeconds(90)
  while(-not $child.HasExited -and (Get-Date)-lt$deadline){Start-Sleep -Milliseconds 250;$child.Refresh()}
  if(-not $child.HasExited){
    Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
    throw "$Name did not complete within 90 seconds. See $out and $err."
  }
  $exitCode=[int]$child.ExitCode
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
$startupLog=Join-Path $scriptRoot 'runtime\start.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $startupLog) | Out-Null
function Write-StartLog([string]$Message){ "$(Get-Date -Format s) $Message" | Add-Content -LiteralPath $startupLog -Encoding UTF8 }
Write-StartLog 'normal-user startup'
  $adminArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $scriptRoot 'Start.ps1')`"","-AdminPhase")
Write-StartLog 'starting elevated service phase'
$process=Start-Process -FilePath (Get-Command powershell.exe).Source -Verb RunAs -ArgumentList $adminArguments -PassThru
$adminDeadline=(Get-Date).AddSeconds(180)
while(-not $process.HasExited -and (Get-Date)-lt$adminDeadline){Start-Sleep -Seconds 1; $process.Refresh()}
if(-not $process.HasExited){throw 'Elevated service startup exceeded 180 seconds. Check runtime\start.log and compose logs.'}
Write-StartLog "elevated service phase returned (PID $($process.Id))"
$adminExitCode=Get-CompletedProcessExitCode $process
if($adminExitCode-ne 0){throw "Elevated service startup failed with exit code $adminExitCode."}
Write-StartLog 'starting OAuth broker'
Invoke-ChildScript 'Start-OAuthBroker.ps1'
Write-StartLog 'starting Developer Workbench'
Invoke-ChildScript 'Start-DeveloperWorkbench.ps1'
# Give services a moment to fully bind before opening the browser.
Start-Sleep -Seconds 2
$urls = @('http://localhost:3000','http://localhost:3001',"http://localhost:$(Get-WorkbenchPort)")
try {
  $browser=$null
  $browserCandidates=@(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Opera\opera.exe')
  )
  foreach($candidate in $browserCandidates){if(-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)){$browser=$candidate;break}}
  if(-not $browser){
    foreach($candidate in @('msedge.exe','chrome.exe','brave.exe','firefox.exe')){
      $command=Get-Command $candidate -ErrorAction SilentlyContinue
      if($command){$browser=$command.Source;break}
    }
  }
  if($browser){
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $browser
    $psi.UseShellExecute = $false
    $psi.Arguments = ('--new-window ' + (($urls | ForEach-Object { '"' + $_ + '"' }) -join ' '))
  } else {
    # Never pass multiple URLs to explorer.exe: it may open File Explorer.
    # ShellExecute the first URL as a safe last resort.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $urls[0]
    $psi.UseShellExecute = $true
  }
  [System.Diagnostics.Process]::Start($psi) | Out-Null
  Write-StartLog 'browser launch requested'
} catch { Write-Warning "Could not open the default browser: $($_.Exception.Message)" }
Write-StartLog 'startup complete'
Write-Host 'All selected services are running. Container services were elevated; native Workbench and OAuth processes run as the current user.'
