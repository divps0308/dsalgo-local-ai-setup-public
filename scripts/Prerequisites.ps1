Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-PrerequisiteLog([string]$Message) {
  $path = if($script:PrerequisiteLogPath){$script:PrerequisiteLogPath}else{Join-Path ([IO.Path]::GetTempPath()) 'dsalgo-prerequisites.log'}
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  "$(Get-Date -Format s) $Message" | Add-Content -LiteralPath $path -Encoding UTF8
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
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
  } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Ensure-Prerequisite([string]$Name,[string]$Command,[string]$WingetId,[string]$FallbackUrl,[string[]]$FallbackArguments=@()) {
  if(Get-Command $Command -ErrorAction SilentlyContinue){ return }
  $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
  if($winget){
    Write-Host "Installing $Name with winget..."
    $safeName = $Name -replace '\W','-'
    $wingetOut = Join-Path ([IO.Path]::GetTempPath()) "dsalgo-winget-$safeName.out.log"
    $wingetErr = Join-Path ([IO.Path]::GetTempPath()) "dsalgo-winget-$safeName.err.log"
    $wingetArgs = "install --id $WingetId --exact --accept-source-agreements --accept-package-agreements --disable-interactivity"
    $wingetProcess = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $wingetOut -RedirectStandardError $wingetErr
    Write-PrerequisiteLog "winget $Name exit $($wingetProcess.ExitCode); stdout $wingetOut; stderr $wingetErr"
    if($wingetProcess.ExitCode -eq 0 -and (Get-Command $Command -ErrorAction SilentlyContinue)){ return }
    Write-Warning "winget could not install $Name; trying the official installer. Details are in the prerequisite log."
  }
  if(-not (Install-OfficialFallback $Name $Command $FallbackUrl $FallbackArguments)) {
    throw "Unable to install $Name automatically. Install it from its official website, then rerun the installer."
  }
}
