param([ValidateSet('Core')][string]$Profile='Core',[string]$BackupPath='')

. "$PSScriptRoot\scripts\Common.ps1"

function Confirm-WSLOverwrite([string[]]$Issues,[string]$Path,[string]$Backup) {
  $details=$Issues -join "`r`n"
  $message=@"
DSAlgo Local AI Setup preserved the existing settings in:
$Path

Merge issues:
$details

The existing memory or processor values are lower than the installer recommendation.

Choose Overwrite to replace only the lower values with the hardware-safe recommendation.
Choose Exit to leave this file unchanged and stop setup.

Backup: $Backup
"@
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $dialog=New-Object Windows.Forms.Form;$dialog.Text='DSAlgo Local AI Setup - WSL configuration';$dialog.TopMost=$true;$dialog.ShowInTaskbar=$true;$dialog.StartPosition='CenterScreen';$dialog.FormBorderStyle='FixedDialog';$dialog.ControlBox=$false;$dialog.MinimizeBox=$false;$dialog.MaximizeBox=$false;$dialog.ClientSize=New-Object Drawing.Size -ArgumentList 520,330
    $text=New-Object Windows.Forms.Label;$text.Text=$message;$text.Location=New-Object Drawing.Point -ArgumentList 18,18;$text.Size=New-Object Drawing.Size -ArgumentList 480,245;$text.AutoSize=$false
    $yes=New-Object Windows.Forms.Button;$yes.Text='Overwrite';$yes.DialogResult=[Windows.Forms.DialogResult]::Yes;$yes.Location=New-Object Drawing.Point -ArgumentList 315,280;$yes.Size=New-Object Drawing.Size -ArgumentList 90,30
    $no=New-Object Windows.Forms.Button;$no.Text='Exit';$no.DialogResult=[Windows.Forms.DialogResult]::No;$no.Location=New-Object Drawing.Point -ArgumentList 415,280;$no.Size=New-Object Drawing.Size -ArgumentList 90,30
    $dialog.Controls.AddRange(@($text,$yes,$no));$dialog.AcceptButton=$yes;$dialog.CancelButton=$no;$dialog.Add_Shown({$dialog.WindowState=[Windows.Forms.FormWindowState]::Normal;$dialog.TopMost=$true;$dialog.Activate();$dialog.BringToFront()})
    $choice=$dialog.ShowDialog();$dialog.Dispose()
    if ($choice -ne [Windows.Forms.DialogResult]::Yes) { throw 'WSL configuration was not changed. Setup exited at the user request.' }
  } catch {
    if ($_.Exception.Message -match '^WSL configuration (?:was not changed|merge was aborted)') { throw }
    try {
      $choice=[Windows.Forms.MessageBox]::Show($message,'DSAlgo Local AI Setup - WSL configuration',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
      if ($choice -ne [Windows.Forms.DialogResult]::Yes) { throw 'WSL configuration was not changed. Setup exited at the user request.' }
    } catch { throw "WSL configuration prompt could not be displayed: $($_.Exception.Message)" }
  }
  return $true
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

function Get-SettingNumber([string]$Key,[string]$Value) {
  if($Key -in @('wsl2.memory','wsl2.swap')) { $m=[regex]::Match($Value,'^\s*(\d+(?:\.\d+)?)\s*(?:GB|GiB)?\s*$','IgnoreCase'); if($m.Success){return [double]$m.Groups[1].Value} }
  if($Key -eq 'wsl2.processors' -and $Value -match '^\s*\d+\s*$'){return [double]$Value.Trim()}
  return $null
}
$lower=@()
foreach($key in @('wsl2.memory','wsl2.processors','wsl2.swap')){
  if($entries.ContainsKey($key)){
    $actual=Get-SettingNumber $key $entries[$key].Value; $wanted=Get-SettingNumber $key $desired[$key]
    if($null -eq $actual -or $actual -lt $wanted){$lower+="[$($key-replace'\.','] ')] is '$($entries[$key].Value)' (installer recommends '$($desired[$key])')."}
  }
}
if($issues.Count){ throw "Cannot safely merge $path. $($issues -join ' ')" }
$overwrite=$false
if($lower.Count){$overwrite=Confirm-WSLOverwrite $lower $path $BackupPath}

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
$changed=$false
for($index=0;$index-lt$lines.Count;$index++){
  $line=$lines[$index]
  foreach($key in @('wsl2.memory','wsl2.processors','wsl2.swap')){if($overwrite -and $entries.ContainsKey($key) -and $entries[$key].Line -eq $index){$replacement="$($key.Split('.')[1])=$($desired[$key])";if($line -ne $replacement){$changed=$true};$line=$replacement}}
  $newLines.Add($line)
  if($inserts.ContainsKey($index)){foreach($entry in $inserts[$index]){$newLines.Add($entry)}}
}
foreach($entry in $newSections){$newLines.Add($entry)}
if ($newLines.Count -ne $lines.Count -or $changed) {
  Set-Content -LiteralPath $path -Value $newLines -Encoding ASCII
  Write-Host "Merged missing DSAlgo settings into $path without replacing existing values. Run 'wsl --shutdown' before restarting Docker Desktop."
} else {
  Write-Host "$path already contains all DSAlgo settings; existing values were preserved."
}
