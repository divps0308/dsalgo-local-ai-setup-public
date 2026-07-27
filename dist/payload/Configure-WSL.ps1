param([ValidateSet('Core')][string]$Profile='Core')

. "$PSScriptRoot\scripts\Common.ps1"

function Confirm-WSLMergeIssue([string[]]$Issues,[string]$Path) {
  $details=$Issues -join "`r`n"
  $message=@"
DSAlgo Local AI Setup preserved the existing settings in:
$Path

Merge issues:
$details

No existing setting will be overwritten. Review the file and ensure its WSL2
memory, processors, and swap values leave enough capacity for Windows, Docker,
and native Ollama.

Choose Yes to continue setup using the preserved settings. Choose No to abort
so you can correct .wslconfig and rerun the installer.
"@
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $choice=[Windows.Forms.MessageBox]::Show($message,'DSAlgo Local AI Setup - WSL configuration',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if ($choice -ne [Windows.Forms.DialogResult]::Yes) { throw "WSL configuration merge was aborted. Remediation: review $Path, resolve the listed settings, then rerun the installer." }
  } catch {
    if ($_.Exception.Message -match '^WSL configuration merge was aborted') { throw }
    Write-Warning $message
    $choice=Read-Host 'Continue setup with preserved .wslconfig settings? Type YES to continue'
    if ($choice -ne 'YES') { throw "WSL configuration merge was aborted. Remediation: review $Path, resolve the listed settings, then rerun the installer." }
  }
  Write-Warning 'Continuing with preserved existing .wslconfig values. DSAlgo resource recommendations may not be applied.'
}

$registry=Get-Registry
$policy=$registry.profiles.core
$path=Join-Path $env:USERPROFILE '.wslconfig'
$desired=[ordered]@{
  'wsl2.memory'="$($policy.dockerMemoryGB)GB"
  'wsl2.processors'="$($policy.dockerProcessors)"
  'wsl2.swap'="$($policy.dockerSwapGB)GB"
  'wsl2.localhostforwarding'='true'
  'experimental.automemoryreclaim'='gradual'
  'experimental.sparsevhd'='true'
}

if(-not(Test-Path -LiteralPath $path)){
  $content=@"
[wsl2]
memory=$($policy.dockerMemoryGB)GB
processors=$($policy.dockerProcessors)
swap=$($policy.dockerSwapGB)GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@.Trim()
  Set-Content -LiteralPath $path -Value $content -Encoding ASCII
  Write-Host "Created $path. Run 'wsl --shutdown' before restarting Docker Desktop."
  return
}

$lines=@(Get-Content -LiteralPath $path)
$section='';$entries=@{};$issues=@();$sectionLastLine=@{}
for($index=0;$index-lt$lines.Count;$index++){
  $line=$lines[$index]
  if($line-match'^\s*(?:#|;|$)'){
    if(-not[string]::IsNullOrWhiteSpace($section)){$sectionLastLine[$section]=$index}
    continue
  }
  if($line-match'^\s*\[([^\]]+)\]\s*(?:[;#].*)?$'){
    $section=$matches[1].Trim().ToLowerInvariant();$sectionLastLine[$section]=$index;continue
  }
  if($line-match'^\s*([^=;#\s][^=]*)\s*=\s*(.*?)\s*(?:[;#].*)?\s*$'){
    if([string]::IsNullOrWhiteSpace($section)){$issues+="Line $($index+1) has a setting outside a section.";continue}
    $key="$section.$($matches[1].Trim().ToLowerInvariant())"
    if($entries.ContainsKey($key)){$issues+="Line $($index+1) duplicates [$section] $($matches[1].Trim()).";continue}
    $entries[$key]=[pscustomobject]@{Line=$index;Value=$matches[2].Trim()};$sectionLastLine[$section]=$index;continue
  }
  $issues+="Line $($index+1) cannot be parsed safely: $line"
  if(-not[string]::IsNullOrWhiteSpace($section)){$sectionLastLine[$section]=$index}
}

foreach($key in $desired.Keys){
  if($entries.ContainsKey($key)-and$entries[$key].Value-ne$desired[$key]){
    $issues+="[$($key-replace'\.','] ')] is '$($entries[$key].Value)' (DSAlgo recommends '$($desired[$key])')."
  }
}
if ($issues.Count) { Confirm-WSLMergeIssue $issues $path }

$missingBySection=@{}
foreach($key in $desired.Keys){
  if($entries.ContainsKey($key)){continue}
  $separator=$key.IndexOf('.');$targetSection=$key.Substring(0,$separator);$targetKey=$key.Substring($separator+1)
  if(-not$missingBySection.ContainsKey($targetSection)){$missingBySection[$targetSection]=[System.Collections.Generic.List[string]]::new()}
  $missingBySection[$targetSection].Add("$targetKey=$($desired[$key])")
}
$inserts=@{};$newSections=[System.Collections.Generic.List[string]]::new()
foreach($targetSection in $missingBySection.Keys){
  if($sectionLastLine.ContainsKey($targetSection)){
    $lineNumber=[int]$sectionLastLine[$targetSection]
    if(-not$inserts.ContainsKey($lineNumber)){$inserts[$lineNumber]=[System.Collections.Generic.List[string]]::new()}
    foreach($entry in $missingBySection[$targetSection]){$inserts[$lineNumber].Add($entry)}
  }else{
    $newSections.Add('');$newSections.Add("[$targetSection]")
    foreach($entry in $missingBySection[$targetSection]){$newSections.Add($entry)}
  }
}
$newLines=[System.Collections.Generic.List[string]]::new()
for($index=0;$index-lt$lines.Count;$index++){
  $newLines.Add($lines[$index])
  if($inserts.ContainsKey($index)){foreach($entry in $inserts[$index]){$newLines.Add($entry)}}
}
foreach($entry in $newSections){$newLines.Add($entry)}
if ($newLines.Count -ne $lines.Count) {
  Set-Content -LiteralPath $path -Value $newLines -Encoding ASCII
  Write-Host "Merged missing DSAlgo settings into $path without replacing existing values. Run 'wsl --shutdown' before restarting Docker Desktop."
} else {
  Write-Host "$path already contains all DSAlgo settings; existing values were preserved."
}
