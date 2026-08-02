Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-PrerequisiteLog([string]$Message) {
  $path = if($script:PrerequisiteLogPath){$script:PrerequisiteLogPath}else{Join-Path ([IO.Path]::GetTempPath()) 'dsalgo-prerequisites.log'}
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  "$(Get-Date -Format s) $Message" | Add-Content -LiteralPath $path -Encoding UTF8
}

function Refresh-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
  $user = [Environment]::GetEnvironmentVariable('Path','User')
  if($machine -or $user){$env:Path=(($machine,$user|Where-Object{$_})-join ';')}
}

function Install-OfficialFallback([string]$Name,[string]$Command,[string]$Url,[string[]]$Arguments=@()) {
  if(Get-Command $Command -ErrorAction SilentlyContinue){ return $true }
  $temp=Join-Path ([IO.Path]::GetTempPath()) ("dsalgo-$Name-installer.exe")
  try {
    Write-Host "Downloading the official $Name installer..."
    Write-PrerequisiteLog "Fallback download started: $Name ($Url)"
    Invoke-WebRequest -Uri $Url -OutFile $temp -UseBasicParsing
    $p=Start-Process -FilePath $temp -ArgumentList $Arguments -Wait -PassThru
    if($p.ExitCode -ne 0){ Write-PrerequisiteLog "Fallback installer failed: $Name exit $($p.ExitCode)"; throw "$Name installer exited with code $($p.ExitCode)." }
    Refresh-ProcessPath
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
  } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Ensure-Prerequisite([string]$Name,[string]$Command,[string]$WingetId,[string]$FallbackUrl,[string[]]$FallbackArguments=@()) {
  if($Command -eq 'python.exe'){
    try{$null=Get-NativePython;return}catch{}
  }
  if($Command -ne 'python.exe' -and (Get-Command $Command -ErrorAction SilentlyContinue)){ return }
  $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
  if($winget){
    Write-Host "Installing $Name with winget..."
    $safeName = $Name -replace '\W','-'
    $wingetOut = Join-Path ([IO.Path]::GetTempPath()) "dsalgo-winget-$safeName.out.log"
    $wingetErr = Join-Path ([IO.Path]::GetTempPath()) "dsalgo-winget-$safeName.err.log"
    $wingetArgs = "install --id $WingetId --exact --accept-source-agreements --accept-package-agreements --disable-interactivity"
    $wingetProcess = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $wingetOut -RedirectStandardError $wingetErr
    Write-PrerequisiteLog "winget $Name exit $($wingetProcess.ExitCode); stdout $wingetOut; stderr $wingetErr"
    Refresh-ProcessPath
    if($wingetProcess.ExitCode -eq 0 -and $Command -eq 'python.exe'){
      try{$null=Get-NativePython;return}catch{}
    }
    if($wingetProcess.ExitCode -eq 0 -and (Get-Command $Command -ErrorAction SilentlyContinue)){ return }
    if($wingetProcess.ExitCode -eq 0 -and $Command -eq 'python.exe'){
      try{$null=Get-NativePython;return}catch{}
    }
    Write-Warning "winget could not install $Name; trying the official installer. Details are in the prerequisite log."
  }
  if(-not (Install-OfficialFallback $Name $Command $FallbackUrl $FallbackArguments)) {
    if($Command -eq 'python.exe'){
      try{$null=Get-NativePython;return}catch{}
    }
    throw "Unable to install $Name automatically. Install it from its official website, then rerun the installer."
  }
}
