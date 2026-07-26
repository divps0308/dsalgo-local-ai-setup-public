param([ValidateSet('TemporalFriendly','AIOnly')][string]$Profile='TemporalFriendly',[switch]$Force)
. "$PSScriptRoot\scripts\Common.ps1"
$r=Get-Registry; $p=if($Profile-eq'TemporalFriendly'){$r.profiles.temporalFriendly}else{$r.profiles.aiOnly}
$path=Join-Path $env:USERPROFILE '.wslconfig'
$content=@" 
[wsl2]
memory=$($p.dockerMemoryGB)GB
processors=$($p.dockerProcessors)
swap=$($p.dockerSwapGB)GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@.Trim()
if((Test-Path $path)-and((Get-Content $path -Raw).Trim()-eq$content)-and-not$Force){
  Write-Host "$path already contains the $Profile profile."
  return
}
if((Test-Path $path)-and-not$Force){Copy-Item $path "$path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"}
$content|Set-Content $path -Encoding ASCII
Write-Host "Wrote $path. Run 'wsl --shutdown' before restarting Docker Desktop."
