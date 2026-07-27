param([Parameter(Mandatory)][string]$Name,[switch]$Remove)
. "$PSScriptRoot\scripts\Common.ps1"
$path=Join-Path $Root 'config\secrets.dpapi.json'; $obj=@{}; if(Test-Path $path){$old=Get-Content $path -Raw|ConvertFrom-Json;foreach($p in $old.PSObject.Properties){$obj[$p.Name]=$p.Value}}
if($Remove){$obj.Remove($Name)|Out-Null}else{$sec=Read-Host "Secret value for $Name" -AsSecureString;$obj[$Name]=ConvertFrom-SecureString $sec}
$obj|ConvertTo-Json|Set-Content $path -Encoding UTF8
Write-Host 'Secret stored with Windows DPAPI for the current Windows user. Restart the stack to apply it.'
