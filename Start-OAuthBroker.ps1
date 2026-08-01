Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
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
if(Test-IsAdmin){throw 'Refusing to start the OAuth broker elevated. Open a normal non-Administrator PowerShell window and run Start.ps1 or Start-OAuthBroker.ps1.'}
$port=Get-OAuthBrokerPort
$python=Get-NativePython
$pythonw=Join-Path (Split-Path -Parent $python) 'pythonw.exe'
if(Test-Path -LiteralPath $pythonw){$python=$pythonw}
$runtime=Join-Path $Root 'runtime\oauth-broker'
$pidFile=Join-Path $runtime 'broker.pid'
$stdoutFile=Join-Path $runtime 'stdout.log'
$stderrFile=Join-Path $runtime 'stderr.log'
New-Item -ItemType Directory -Force $runtime|Out-Null
if(Test-OAuthBroker){
  Write-Host "MCP OAuth broker is already running at http://localhost:$port"
  exit 0
}
if(Test-Path $pidFile){Remove-Item -LiteralPath $pidFile -Force}
$app=Join-Path $Root 'oauth-broker\app.py'
$process=Start-Process -FilePath $python -ArgumentList @("`"$app`"",'--port',"$port") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
@{
  pid=$process.Id
  executable=$python
  app=$app
  startedAt=$process.StartTime.ToUniversalTime().ToString('o')
}|ConvertTo-Json|Set-Content -LiteralPath $pidFile -Encoding UTF8
$end=(Get-Date).AddSeconds(30)
do{
  Start-Sleep 1
  if(Test-OAuthBroker){Write-Host "MCP OAuth broker started at http://localhost:$port";exit 0}
  if($process.HasExited){
    $process.Refresh()
    $detail=''
    if(Test-Path -LiteralPath $stderrFile){
      $lastError=(Get-Content -LiteralPath $stderrFile -Tail 8 -ErrorAction SilentlyContinue)-join' '
      if($lastError){$detail=" Last error: $lastError"}
    }
    throw "MCP OAuth broker exited with code $($process.ExitCode). See $stderrFile and logs\oauth-broker.log.$detail"
  }
}while((Get-Date)-lt$end)
throw 'MCP OAuth broker did not become ready within 30 seconds.'
