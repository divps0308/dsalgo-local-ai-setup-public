Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\scripts\Common.ps1"

$progressPath=Join-Path ([IO.Path]::GetTempPath()) ("dsalgo-lifecycle-progress-{0}.log" -f [guid]::NewGuid())
$previous=[Environment]::GetEnvironmentVariable('DSALGO_LIFECYCLE_PROGRESS','Process')
try {
  [Environment]::SetEnvironmentVariable('DSALGO_LIFECYCLE_PROGRESS',$progressPath,'Process')
  Write-LifecyclePhase 'test-current-step'
  $line=Get-Content -LiteralPath $progressPath -Tail 1
  if($line-notmatch'^\d{4}-\d{2}-\d{2}T.*\|test-current-step$'){
    throw "Lifecycle progress record was invalid: $line"
  }
} finally {
  [Environment]::SetEnvironmentVariable('DSALGO_LIFECYCLE_PROGRESS',$previous,'Process')
  Remove-Item -LiteralPath $progressPath -Force -ErrorAction SilentlyContinue
}

Write-Host 'Lifecycle progress tests passed.'
