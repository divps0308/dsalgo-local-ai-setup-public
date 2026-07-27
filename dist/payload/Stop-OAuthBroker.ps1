Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$commonPath = Join-Path $PSScriptRoot 'scripts\Common.ps1'
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){$PSScriptRoot}else{Split-Path -Parent $PSCommandPath}
$pidFile=Join-Path $Root 'runtime\oauth-broker\broker.pid'
if(-not(Test-Path $pidFile)){Write-Host 'MCP OAuth broker is not running.';exit 0}
$metadata=Get-Content -LiteralPath $pidFile -Raw|ConvertFrom-Json
$brokerPid=[int]$metadata.pid
$process=Get-Process -Id $brokerPid -ErrorAction SilentlyContinue
if($process){
  $expectedExecutable=[IO.Path]::GetFullPath([string]$metadata.executable)
  $actualExecutable=if([string]::IsNullOrWhiteSpace($process.Path)){$expectedExecutable}else{[IO.Path]::GetFullPath($process.Path)}
  $expectedStart=[datetime]::Parse([string]$metadata.startedAt).ToUniversalTime()
  $actualStart=$process.StartTime.ToUniversalTime()
  if($actualExecutable-ne$expectedExecutable-or[math]::Abs(($actualStart-$expectedStart).TotalSeconds)-gt 2){
    throw "PID $brokerPid does not belong to the MCP OAuth broker; refusing to stop it."
  }
  $process.Kill()
  try{Wait-Process -Id $brokerPid -Timeout 15 -ErrorAction Stop}catch{
    $remaining=Get-Process -Id $brokerPid -ErrorAction SilentlyContinue
    if($remaining){$remaining.Kill()}
  }
}
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Write-Host 'MCP OAuth broker stopped.'
