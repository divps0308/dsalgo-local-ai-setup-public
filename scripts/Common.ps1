Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $null
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  # Common.ps1 is loaded both from scripts\ and from root-level child scripts.
  # Only the former needs its parent directory as the installation root.
  $locationLeaf = Split-Path -Leaf $PSScriptRoot
  $Root = if ($locationLeaf -ieq 'scripts') { Split-Path -Parent $PSScriptRoot } else { $PSScriptRoot }
}
if ([string]::IsNullOrWhiteSpace($Root)) {
  try { $Root = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { }
}
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Cannot determine the DSAlgo Local AI Setup directory.' }
function Test-IsAdmin { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Assert-Admin { if(-not(Test-IsAdmin)){throw 'Run PowerShell as Administrator.'} }
function Write-LifecyclePhase([string]$Name) {
  if([string]::IsNullOrWhiteSpace($Name)){return}
  Write-Host "Phase: $Name"
  $progressPath=[Environment]::GetEnvironmentVariable('DSALGO_LIFECYCLE_PROGRESS','Process')
  if(-not[string]::IsNullOrWhiteSpace($progressPath)){
    try{"$(Get-Date -Format s)|$Name" | Add-Content -LiteralPath $progressPath -Encoding UTF8}catch{}
  }
}
function Get-CompletedProcessExitCode([Diagnostics.Process]$Process) {
  if (-not $Process) { throw 'The child process could not be started.' }
  $Process.WaitForExit()
  $Process.Refresh()
  return [int]$Process.ExitCode
}
function Assert-Command([string]$Name){if(-not(Get-Command $Name -ErrorAction SilentlyContinue)){throw "Required command not found: $Name"}}
function Get-DockerExecutable {
  $command=Get-Command docker.exe -ErrorAction SilentlyContinue
  if($command-and-not[string]::IsNullOrWhiteSpace([string]$command.Source)){return $command.Source}
  $candidates=@()
  if($env:ProgramFiles){$candidates+=Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'}
  if(${env:ProgramFiles(x86)}){$candidates+=Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\resources\bin\docker.exe'}
  foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate){return $candidate}}
  throw 'Docker CLI was not found. Start or repair Docker Desktop, then retry.'
}
function Test-DockerAvailable { try{$null=Get-DockerExecutable;return $true}catch{return $false} }
function Assert-WSLReady {
  $wsl=Get-Command wsl.exe -ErrorAction SilentlyContinue
  if(-not$wsl){throw 'WSL was not found. Rerun Install.exe and restart Windows if prompted.'}
  foreach($featureName in @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform')){
    $feature=Get-WindowsOptionalFeature -Online -FeatureName $featureName
    if($feature.State-ne 'Enabled'){
      throw "Required Windows feature $featureName is not enabled. Rerun Install.exe and restart Windows if prompted."
    }
  }
}
function Ensure-DockerDesktop([int]$Seconds=180) {
  Assert-WSLReady
  $docker=Get-DockerExecutable
  try{& $docker info *> $null;if($LASTEXITCODE-eq 0){return}}catch{}
  $desktop=Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
  if(-not(Test-Path -LiteralPath $desktop)){throw 'Docker Desktop is not installed. Rerun Install.exe, then retry.'}
  if(-not(Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)){
    Start-Process -FilePath $desktop -WindowStyle Hidden | Out-Null
  }
  Wait-Docker -Seconds $Seconds
}
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
function Wait-Docker([int]$Seconds=180){$docker=Get-DockerExecutable;$end=(Get-Date).AddSeconds($Seconds);do{try{& $docker info *> $null;if($LASTEXITCODE-eq0){return}}catch{};Start-Sleep 3}while((Get-Date)-lt$end);throw 'Docker Desktop did not become ready.'}
function Get-OllamaExecutable {
  $command = Get-Command ollama.exe -ErrorAction SilentlyContinue
  if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) { return $command.Source }
  $candidates = @()
  if ($env:LOCALAPPDATA) {
    $candidates += Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    $candidates += Join-Path $env:LOCALAPPDATA 'Ollama\ollama.exe'
  }
  if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles 'Ollama\ollama.exe' }
  foreach ($candidate in $candidates) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
  throw 'Ollama was not found. Run Install.exe to install Ollama, then retry.'
}
function Test-OllamaAvailable([string]$BaseUrl = 'http://127.0.0.1:11434') {
  try { $response = Invoke-WebRequest "$BaseUrl/api/tags" -UseBasicParsing -TimeoutSec 5; return ($response.StatusCode -eq 200) } catch { return $false }
}
function Ensure-Ollama([int]$Seconds = 90) {
  if (Test-OllamaAvailable) { return }
  $ollama = Get-OllamaExecutable
  $runtime = Join-Path $Root 'runtime'; New-Item -ItemType Directory -Force -Path $runtime | Out-Null
  $stdout = Join-Path $runtime 'ollama-serve.stdout.log'; $stderr = Join-Path $runtime 'ollama-serve.stderr.log'
  if (-not (Get-Process -Name 'ollama' -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $ollama -ArgumentList @('serve') -WorkingDirectory $Root -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr | Out-Null
  }
  $deadline = (Get-Date).AddSeconds($Seconds)
  do { if (Test-OllamaAvailable) { return }; Start-Sleep -Seconds 2 } while ((Get-Date) -lt $deadline)
  throw "Ollama did not become ready within $Seconds seconds. See $stdout and $stderr."
}
function Stop-DSAlgoProcesses {
  param([string]$InstallRoot = $Root)
  $normalized = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') + '\'
  $currentPid = [Diagnostics.Process]::GetCurrentProcess().Id
  try {
    $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $protected = [Collections.Generic.HashSet[int]]::new()
    $cursor = $currentPid
    while ($cursor -and $protected.Add([int]$cursor)) {
      $parent = $allProcesses | Where-Object ProcessId -eq $cursor | Select-Object -First 1
      $cursor = if ($parent) { [int]$parent.ParentProcessId } else { 0 }
    }
    $allProcesses | ForEach-Object {
      if ($protected.Contains([int]$_.ProcessId)) { return }
      $path = [string]$_.ExecutablePath
      $command = [string]$_.CommandLine
      if (($path -and $path.StartsWith($normalized, [StringComparison]::OrdinalIgnoreCase)) -or ($command -and $command.IndexOf($normalized, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
        try { Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue } catch { }
      }
    }
  } catch { Write-Warning "Could not enumerate all DSAlgo processes: $($_.Exception.Message)" }
}function Get-SystemIanaTimeZone([string]$WindowsTimeZoneId = [TimeZoneInfo]::Local.Id) {
  if([string]::IsNullOrWhiteSpace($WindowsTimeZoneId)){throw 'Windows did not report a system time-zone identifier.'}
  if($WindowsTimeZoneId.Contains('/')){return $WindowsTimeZoneId}
  $mappingFile=Join-Path $Root 'scripts\windows-time-zones.json'
  if(-not(Test-Path -LiteralPath $mappingFile)){throw "Windows-to-IANA time-zone mapping was not found: $mappingFile"}
  $mapping=Get-Content -LiteralPath $mappingFile -Raw|ConvertFrom-Json
  $property=$mapping.mappings.PSObject.Properties[$WindowsTimeZoneId]
  if(-not $property-or[string]::IsNullOrWhiteSpace([string]$property.Value)){throw "Windows time zone '$WindowsTimeZoneId' has no IANA mapping. Set TZ in .env to a valid IANA time zone and retry."}
  return [string]$property.Value
}
function Resolve-TimeZonePlaceholder([string]$Text,[string]$WindowsTimeZoneId = [TimeZoneInfo]::Local.Id) {
  if($Text-notmatch'detect-system-timezone-during-install'){return $Text}
  return $Text.Replace('detect-system-timezone-during-install',(Get-SystemIanaTimeZone $WindowsTimeZoneId))
}
function Ensure-Env {
  $envFile=Join-Path $Root '.env'; if(-not(Test-Path $envFile)){Copy-Item (Join-Path $Root '.env.example') $envFile}
  $text=Get-Content $envFile -Raw
  if($text -match 'change-me-generated-by-install'){ $key=[Convert]::ToBase64String((1..36|ForEach-Object{Get-Random -Maximum 256})); $text=$text.Replace('change-me-generated-by-install',$key) }
  $text=Resolve-TimeZonePlaceholder $text
  if($text -notmatch '(?m)^POSTGRES_PASSWORD='){ $val=[Convert]::ToBase64String((1..24|ForEach-Object{Get-Random -Maximum 256})); $text += "`nPOSTGRES_PASSWORD=$val" }
  Set-Content $envFile $text -Encoding UTF8
}
function Compose([string[]]$ComposeArgs){
  if(-not $ComposeArgs -or @($ComposeArgs).Count -eq 0){throw 'Compose requires at least one Docker Compose argument.'}
  Push-Location $Root
  try {
    $docker=Get-DockerExecutable
    $safeName=($ComposeArgs -join '-') -replace '[^A-Za-z0-9._-]','-'
    $out=Join-Path $Root "runtime\compose-$safeName.out.log"
    $err=Join-Path $Root "runtime\compose-$safeName.err.log"
    $arguments=@('compose')+$ComposeArgs
    Write-Host "Docker Compose: $($ComposeArgs -join ' ')"
    $process=Start-Process -FilePath $docker -ArgumentList $arguments -WorkingDirectory $Root -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    if($process.ExitCode-ne 0){throw "docker compose failed: $($ComposeArgs -join ' ') (exit $($process.ExitCode)). See $out and $err."}
    Write-Host "Docker Compose completed: $($ComposeArgs -join ' ')"
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
