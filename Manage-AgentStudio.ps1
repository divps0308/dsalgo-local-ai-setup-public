param([ValidateSet('Install','Update','Repair','Uninstall')] [string]$Action='Install')
switch($Action){
 'Install' { & "$PSScriptRoot\Install.ps1" -SkipModels }
 'Update' { & "$PSScriptRoot\Update.ps1" -SkipModels }
 'Repair' { & "$PSScriptRoot\Repair.ps1" }
 'Uninstall' { docker compose -f "$PSScriptRoot\docker-compose.yml" stop agent-studio; docker compose -f "$PSScriptRoot\docker-compose.yml" rm -f agent-studio }
}
