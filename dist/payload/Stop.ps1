param([switch]$RemoveRuntimeSecrets)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { } }
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
Invoke-ChildScript 'Stop-DeveloperWorkbench.ps1'
Invoke-ChildScript 'Stop-OAuthBroker.ps1'
if(-not(Test-DockerAvailable)){throw 'Docker CLI was not found, so container services could not be stopped. Start or repair Docker Desktop, then retry.'}
Compose @('stop')
if($RemoveRuntimeSecrets){
  $secret=Join-Path $Root 'runtime\secrets.json'
  Remove-Item -LiteralPath $secret -Force -ErrorAction SilentlyContinue
}
Write-Host 'Services stopped. Containers, images, volumes, and configuration were retained.'
