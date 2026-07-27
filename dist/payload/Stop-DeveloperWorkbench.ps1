$commonPath = Join-Path $PSScriptRoot 'scripts\Common.ps1'
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){$PSScriptRoot}else{Split-Path -Parent $PSCommandPath}
$pidFile=Join-Path $Root 'runtime\developer-workbench\workbench.pid'
if(-not(Test-Path $pidFile)){Write-Host 'Developer Workbench is not running.';exit 0}
$metadata=Get-Content -LiteralPath $pidFile -Raw|ConvertFrom-Json
$workbenchPid=[int]$metadata.pid
$process=Get-Process -Id $workbenchPid -ErrorAction SilentlyContinue
if($process){
  $expectedExecutable=[IO.Path]::GetFullPath([string]$metadata.executable)
  $actualExecutable=if([string]::IsNullOrWhiteSpace($process.Path)){$expectedExecutable}else{[IO.Path]::GetFullPath($process.Path)}
  $expectedStart=[datetime]::Parse([string]$metadata.startedAt).ToUniversalTime()
  $actualStart=$process.StartTime.ToUniversalTime()
  if($actualExecutable-ne$expectedExecutable-or[math]::Abs(($actualStart-$expectedStart).TotalSeconds)-gt 2){
    throw "PID $workbenchPid does not belong to Developer Workbench; refusing to stop it."
  }
  Stop-Process -Id $workbenchPid
  try{Wait-Process -Id $workbenchPid -Timeout 15 -ErrorAction Stop}catch{Stop-Process -Id $workbenchPid -Force}
}
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Write-Host 'Developer Workbench stopped.'
