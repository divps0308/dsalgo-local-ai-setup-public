Set-StrictMode -Version Latest

function Get-InstallStatePath { Join-Path $Root 'runtime\install-state.json' }

function Get-InstallState {
  $path=Get-InstallStatePath
  if(Test-Path -LiteralPath $path){return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
  return [pscustomobject]@{
    schemaVersion=1; completedSteps=@(); installed=@{
      python=$false; ollama=$false; docker=$false
      wslFeature=$false; virtualMachinePlatform=$false
    }; pulledModels=@(); wslConfigBackup=$null
  }
}

function Save-InstallState($State) {
  $path=Get-InstallStatePath
  $directory=Split-Path -Parent $path
  New-Item -ItemType Directory -Force -Path $directory|Out-Null
  $temporary="$path.tmp"
  $State|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Complete-InstallStep($State,[string]$Step) {
  if($Step -notin @($State.completedSteps)){$State.completedSteps=@($State.completedSteps)+$Step}
  Save-InstallState $State
}
