Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ("dsalgo-install-state-{0}" -f [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'runtime')|Out-Null
  $Root=$testRoot
  . "$PSScriptRoot\..\scripts\Install-State.ps1"

  $empty=Get-InstallState
  if($empty.schemaVersion-ne2-or$empty.owned.ollamaProfile-ne$false){throw 'New install state must include conservative Ollama profile ownership.'}

  [ordered]@{schemaVersion=1;completedSteps=@();installed=[ordered]@{python=$false;ollama=$false;docker=$false;wslFeature=$false;virtualMachinePlatform=$false};pulledModels=@();wslConfigBackup=$null}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Get-InstallStatePath) -Encoding UTF8
  $migrated=Get-InstallState
  if($migrated.owned.ollamaProfile-ne$false){throw 'Legacy install state must preserve an unowned Ollama profile.'}
} finally {
  if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
}

Write-Host 'Install-state ownership tests passed.'
