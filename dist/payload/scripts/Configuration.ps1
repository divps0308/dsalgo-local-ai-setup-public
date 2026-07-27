Set-StrictMode -Version Latest

function Use-PersonalConfiguration {
  $pairs=@{
    'personal-agents.json'='agents.json'
    'personal-models.json'='models.json'
    'personal-projects.json'='projects.json'
    'personal-runtime-policy.json'='runtime-policy.json'
  }
  foreach($sourceName in $pairs.Keys){
    $source=Join-Path $Root "config\$sourceName"
    if(Test-Path -LiteralPath $source){
      Copy-Item -LiteralPath $source -Destination (Join-Path $Root "config\$($pairs[$sourceName])") -Force
    }
  }
}

function Assert-GenericConfiguration {
  foreach($name in @('agents.json','models.json','projects.json','runtime-policy.json')){
    $path=Join-Path $Root "config\$name"
    if(-not(Test-Path -LiteralPath $path)){throw "Required configuration is missing: $path"}
    $null=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  }
  $agents=Get-Content -LiteralPath (Join-Path $Root 'config\agents.json') -Raw|ConvertFrom-Json
  if($null-eq$agents.PSObject.Properties['agents']-or$null-eq$agents.PSObject.Properties['mcpServers']){
    throw 'config\agents.json must contain agents and mcpServers arrays.'
  }
  $projects=Get-Content -LiteralPath (Join-Path $Root 'config\projects.json') -Raw|ConvertFrom-Json
  if($null-eq$projects.PSObject.Properties['projects']){
    throw 'config\projects.json must contain a projects array.'
  }
  $policy=Get-Content -LiteralPath (Join-Path $Root 'config\runtime-policy.json') -Raw|ConvertFrom-Json
  if($policy.mode-notin@('online','restricted-online','strict-offline')){
    throw 'config\runtime-policy.json contains an unsupported mode.'
  }
}
