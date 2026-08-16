param([switch]$RemoveImages,[switch]$Force,[switch]$Elevated,[switch]$WizardChild)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { } }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if(-not$WizardChild -and -not$Elevated){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'scripts\LifecycleWizard.ps1') -Operation Remove;exit $LASTEXITCODE}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'Cannot determine the installed DSAlgo Local AI Setup directory.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $isPowerShellHost = [IO.Path]::GetFileName($hostExe) -match '^(powershell|pwsh)(\.exe)?$'
  $forward = @('-Elevated','-WizardChild'); if($RemoveImages){$forward+='-RemoveImages'}; if($Force){$forward+='-Force'}
  $arguments = if ($isPowerShellHost) { @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $scriptRoot 'Remove.ps1')`"") + $forward } else { $forward }
  $elevatedProcess = Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $arguments -PassThru
  $elevatedProcess.WaitForExit(); $elevatedProcess.Refresh()
  exit $elevatedProcess.ExitCode
}
$commonPath = Join-Path $scriptRoot 'scripts\Common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { throw "Required lifecycle script was not found: $commonPath" }
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = $scriptRoot
Write-LifecyclePhase 'confirming-removal'
if(-not$Force){
  $answer=Read-Host 'Remove all DS_ALGO Local AI containers and project services? Data volumes and configuration will be retained. Type REMOVE'
  if($answer-ne'REMOVE'){Write-Host 'Cancelled.';exit 1}
}
Write-LifecyclePhase 'stopping-native-services'
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-DeveloperWorkbench.ps1')
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-OAuthBroker.ps1')
$arguments=@('down','--remove-orphans')
if($RemoveImages){$arguments+=@('--rmi','local')}
Write-LifecyclePhase 'removing-container-services'
Compose $arguments
Write-LifecyclePhase 'complete'
Write-Host 'Project containers and services were removed. Persistent volumes, models, and configuration were retained.'
