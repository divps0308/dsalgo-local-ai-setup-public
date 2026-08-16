param([switch]$Elevated,[switch]$WizardChild)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { } }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if(-not$WizardChild -and -not$Elevated){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'scripts\LifecycleWizard.ps1') -Operation Repair;exit $LASTEXITCODE}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'Cannot determine the installed DSAlgo Local AI Setup directory.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $isPowerShellHost = [IO.Path]::GetFileName($hostExe) -match '^(powershell|pwsh)(\.exe)?$'
  $arguments = if ($isPowerShellHost) { @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $scriptRoot 'Repair.ps1')`"",'-Elevated','-WizardChild') } else { @('-Elevated','-WizardChild') }
  $elevatedProcess = Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $arguments -PassThru
  $elevatedProcess.WaitForExit(); $elevatedProcess.Refresh()
  exit $elevatedProcess.ExitCode
}
$commonPath = Join-Path $scriptRoot 'scripts\Common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { throw "Required lifecycle script was not found: $commonPath" }
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = $scriptRoot
Invoke-Expression (Get-Content -LiteralPath (Join-Path $scriptRoot 'scripts\Configuration.ps1') -Raw)
Invoke-Expression (Get-Content -LiteralPath (Join-Path $scriptRoot 'scripts\Shortcuts.ps1') -Raw)
Assert-Admin
Write-LifecyclePhase 'checking-docker'
Wait-Docker
Write-LifecyclePhase 'stopping-services'
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-DeveloperWorkbench.ps1')
& (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Stop-OAuthBroker.ps1')
Compose @('down','--remove-orphans')
Write-LifecyclePhase 'validating-configuration'
Assert-GenericConfiguration
Ensure-Env
Prepare-RuntimeSecrets
Write-LifecyclePhase 'building-images'
Compose @('build')
Write-LifecyclePhase 'creating-containers'
Compose @('create','--remove-orphans')
Write-LifecyclePhase 'refreshing-shortcuts'
Install-LocalAIShortcuts
Write-LifecyclePhase 'complete'
Write-Host 'Repair complete. Images were rebuilt and containers recreated in the stopped state. Run .\Start.ps1 when ready.'
