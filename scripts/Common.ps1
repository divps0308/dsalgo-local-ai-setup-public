Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
function Test-IsAdmin { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Assert-Admin { if(-not(Test-IsAdmin)){throw 'Run PowerShell as Administrator.'} }
function Assert-Command([string]$Name){if(-not(Get-Command $Name -ErrorAction SilentlyContinue)){throw "Required command not found: $Name"}}
function Get-NativePython {
  $candidates=@()
  $command=Get-Command python.exe -ErrorAction SilentlyContinue
  if($command){$candidates+=$command.Source}
  $candidates+=@(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe') -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
  $candidates+=@(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'Python3*\python.exe') -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
  foreach($candidate in $candidates|Select-Object -Unique){
    if(-not(Test-Path -LiteralPath $candidate)){continue}
    try{
      $version=& $candidate --version 2>&1
      if($LASTEXITCODE-eq 0-and"$version"-match'^Python 3\.'){return $candidate}
    }catch{}
  }
  throw 'Native Python 3 was not found. Run Install.ps1 as Administrator to install it.'
}
function Get-WorkbenchPort {
  if($env:DEVELOPER_WORKBENCH_PORT){return [int]$env:DEVELOPER_WORKBENCH_PORT}
  $envFile=Join-Path $Root '.env'
  if(Test-Path $envFile){
    $match=[regex]::Match((Get-Content -LiteralPath $envFile -Raw),'(?m)^DEVELOPER_WORKBENCH_PORT=(\d+)\s*$')
    if($match.Success){return [int]$match.Groups[1].Value}
  }
  return 3002
}
function Test-Workbench {
  $port=Get-WorkbenchPort
  try{$response=Invoke-WebRequest "http://localhost:$port/health" -UseBasicParsing -TimeoutSec 5;return ($response.StatusCode -eq 200)}catch{return $false}
}
function Get-OAuthBrokerPort {
  if($env:OAUTH_BROKER_PORT){return [int]$env:OAUTH_BROKER_PORT}
  $envFile=Join-Path $Root '.env'
  if(Test-Path $envFile){
    $match=[regex]::Match((Get-Content -LiteralPath $envFile -Raw),'(?m)^OAUTH_BROKER_PORT=(\d+)\s*$')
    if($match.Success){return [int]$match.Groups[1].Value}
  }
  return 3003
}
function Test-OAuthBroker {
  $port=Get-OAuthBrokerPort
  try{$response=Invoke-WebRequest "http://localhost:$port/health" -UseBasicParsing -TimeoutSec 5;return ($response.StatusCode -eq 200)}catch{return $false}
}
function Wait-Docker([int]$Seconds=180){$end=(Get-Date).AddSeconds($Seconds);do{try{docker info *> $null;return}catch{Start-Sleep 3}}while((Get-Date)-lt$end);throw 'Docker Desktop did not become ready.'}
function Ensure-Env {
  $envFile=Join-Path $Root '.env'; if(-not(Test-Path $envFile)){Copy-Item (Join-Path $Root '.env.example') $envFile}
  $text=Get-Content $envFile -Raw
  if($text -match 'change-me-generated-by-install'){ $key=[Convert]::ToBase64String((1..36|ForEach-Object{Get-Random -Maximum 256})); $text=$text.Replace('change-me-generated-by-install',$key) }
  foreach($name in @('POSTGRES_PASSWORD','TEMPORAL_POSTGRES_PASSWORD')){ if($text -notmatch "(?m)^$name="){ $val=[Convert]::ToBase64String((1..24|ForEach-Object{Get-Random -Maximum 256})); $text += "`n$name=$val" } }
  Set-Content $envFile $text -Encoding UTF8
}
function Compose([string[]]$ComposeArgs){
  if(-not $ComposeArgs -or $ComposeArgs.Count -eq 0){throw 'Compose requires at least one Docker Compose argument.'}
  Push-Location $Root
  try {
    & docker compose @ComposeArgs
    if($LASTEXITCODE-ne 0){throw "docker compose failed: $($ComposeArgs -join ' ')"}
  } finally {
    Pop-Location
  }
}
function Get-Registry { Get-Content (Join-Path $Root 'config\models.json') -Raw | ConvertFrom-Json }
function Get-ModelTags { $r=Get-Registry; @($r.models.general.ollamaTag,$r.models.coder.ollamaTag,$r.models.reasoning.ollamaTag,$r.models.embedding.ollamaTag) }
function Prepare-RuntimeSecrets {
  $runtime=Join-Path $Root 'runtime'; New-Item -ItemType Directory -Force $runtime|Out-Null
  $encrypted=Join-Path $Root 'config\secrets.dpapi.json'; $out=Join-Path $runtime 'secrets.json'
  if(Test-Path $encrypted){ $items=Get-Content $encrypted -Raw|ConvertFrom-Json; $plain=@{}; foreach($p in $items.PSObject.Properties){$secure=ConvertTo-SecureString $p.Value; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure);try{$plain[$p.Name]=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}; $plain|ConvertTo-Json|Set-Content $out -Encoding UTF8 } else { '{}'|Set-Content $out -Encoding UTF8 }
}
