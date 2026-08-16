param([ValidateSet('Start','Stop','Repair','Remove','Uninstall')][string]$Operation)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$form=New-Object Windows.Forms.Form; $form.Text="DSAlgo Local AI Setup - $Operation"; $form.Size=New-Object Drawing.Size(820,560); $form.StartPosition='CenterScreen'; $form.TopMost=$true
$title=New-Object Windows.Forms.Label; $title.Text="$Operation DSAlgo Local AI Setup"; $title.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold); $title.Location=New-Object Drawing.Point(24,18); $title.Size=New-Object Drawing.Size(740,35); $form.Controls.Add($title)
$step=New-Object Windows.Forms.Label; $step.Text='Ready'; $step.Location=New-Object Drawing.Point(24,66); $step.Size=New-Object Drawing.Size(755,22); $step.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold); $form.Controls.Add($step)
$bar=New-Object Windows.Forms.ProgressBar; $bar.Location=New-Object Drawing.Point(24,92); $bar.Size=New-Object Drawing.Size(755,18); $bar.Style='Marquee'; $bar.MarqueeAnimationSpeed=0; $form.Controls.Add($bar)
$output=New-Object Windows.Forms.TextBox; $output.Multiline=$true; $output.ReadOnly=$true; $output.ScrollBars='Both'; $output.Location=New-Object Drawing.Point(24,122); $output.Size=New-Object Drawing.Size(755,328); $output.Font=New-Object Drawing.Font('Consolas',9); $form.Controls.Add($output)
$next=New-Object Windows.Forms.Button; $next.Text='Next'; $next.Location=New-Object Drawing.Point(570,475); $next.Size=New-Object Drawing.Size(95,30); $form.Controls.Add($next)
$cancel=New-Object Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Location=New-Object Drawing.Point(680,475); $cancel.Size=New-Object Drawing.Size(95,30); $form.Controls.Add($cancel)
$purge=$null
if($Operation -eq 'Uninstall'){
  $purge=New-Object Windows.Forms.CheckBox; $purge.Text='Permanently remove installer-owned Docker data, models, and an installer-created Ollama profile'; $purge.AutoSize=$true; $purge.Checked=$false; $purge.Location=New-Object Drawing.Point(24,462); $form.Controls.Add($purge)
  $next.Location=New-Object Drawing.Point(570,510); $cancel.Location=New-Object Drawing.Point(680,510); $form.ClientSize=New-Object Drawing.Size(820,550)
}
$script:child=$null; $script:started=$false; $script:completedAt=$null; $script:outOffset=0; $script:errOffset=0; $script:phaseOffset=0
function Append([string]$s){if($s){$output.AppendText($s.TrimEnd()+[Environment]::NewLine);$output.SelectionStart=$output.TextLength;$output.ScrollToCaret()}}
function Set-Step([string]$name){if($name){$step.Text=($name -replace '[-_]',' ');$step.Text=$step.Text.Substring(0,1).ToUpperInvariant()+$step.Text.Substring(1)}}
function Read-NewText([string]$path,[string]$kind){
  if(-not(Test-Path -LiteralPath $path)){return}
  $text=Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
  if([string]::IsNullOrEmpty($text)){return}
  $offset=if($kind-eq'out'){$script:outOffset}else{$script:errOffset}
  if($text.Length-le$offset){return}
  $newText=$text.Substring($offset)
  if($kind-eq'out'){$script:outOffset=$text.Length}else{$script:errOffset=$text.Length}
  foreach($line in ($newText -split "`r?`n")){if($line){Append $(if($kind-eq'err'){"ERROR: $line"}else{$line})}}
}
function Read-NewPhase {
  if(-not(Test-Path -LiteralPath $script:phase)){return}
  $text=Get-Content -LiteralPath $script:phase -Raw -ErrorAction SilentlyContinue
  if([string]::IsNullOrEmpty($text)-or$text.Length-le$script:phaseOffset){return}
  $newText=$text.Substring($script:phaseOffset);$script:phaseOffset=$text.Length
  foreach($line in ($newText -split "`r?`n")){if($line-match'\|(.+)$'){Set-Step $matches[1]}}
}
function Get-WizardExitCode {
  if(-not $script:child){ return -1 }
  try {
    $script:child.WaitForExit()
    $script:child.Refresh()
    return [int]$script:child.ExitCode
  } catch { }
  # A completed child should always expose ExitCode. Keep -1 only for a
  # genuinely unavailable process handle, never for a null property value.
  return -1
}
function Update-WizardProgress {
  Read-NewText $script:out 'out'; Read-NewText $script:err 'err'; Read-NewPhase
  if($script:child -and $script:child.HasExited){
    $script:timer.Stop(); $script:child.Refresh()
    $exitCode=Get-WizardExitCode
    Append ("Completed with exit code {0}" -f $exitCode)
    $bar.MarqueeAnimationSpeed=0;$bar.Style='Continuous';$bar.Value=100
    Set-Step $(if($exitCode-eq0){'Complete'}else{'Failed'})
    $cancel.Enabled=$false; $next.Text='Close'; $next.Enabled=$true
    $script:completedAt=Get-Date
    $next.Add_Click({$form.Close()})
  }
  if($script:completedAt -and ((Get-Date)-$script:completedAt).TotalSeconds -ge 2){$form.Close()}
}
$next.Add_Click({
  if($script:started){return}
  $script:started=$true; $next.Enabled=$false
  $bar.Style='Marquee';$bar.MarqueeAnimationSpeed=30;Set-Step 'Starting'
  Append "Starting $Operation..."
  $script:out=Join-Path $root ("runtime\wizard-{0}.stdout.log" -f $Operation)
  $script:err=Join-Path $root ("runtime\wizard-{0}.stderr.log" -f $Operation)
  $script:phase=Join-Path $root ("runtime\wizard-{0}.progress.log" -f $Operation)
  New-Item -ItemType Directory -Force -Path (Split-Path $script:out) | Out-Null
  Set-Content -LiteralPath $script:out,$script:err,$script:phase -Value '' -Encoding UTF8
  $script:outOffset=0;$script:errOffset=0;$script:phaseOffset=0
  [Environment]::SetEnvironmentVariable('DSALGO_LIFECYCLE_PROGRESS',$script:phase,'Process')
  $scriptPath=Join-Path $root ($Operation+'.ps1')
  # Start-Process flattens ArgumentList; quote paths containing spaces so
  # PowerShell receives the complete -File value.
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$scriptPath+'"'),'-WizardChild')
  if($Operation -in @('Remove','Uninstall')){$args+='-Force'}
  if($Operation -eq 'Uninstall' -and $purge.Checked){$args+=@('-RemoveData','-RemoveModels','-RemoveImages')}
  $script:child=Start-Process powershell.exe -ArgumentList $args -WorkingDirectory $root -PassThru -RedirectStandardOutput $script:out -RedirectStandardError $script:err
  $script:timer=New-Object Windows.Forms.Timer; $script:timer.Interval=400
  $script:timer.Add_Tick({Update-WizardProgress}); $script:timer.Start()
})
$cancel.Add_Click({if($script:child -and -not $script:child.HasExited){Stop-Process -Id $script:child.Id -Force -ErrorAction SilentlyContinue};$form.Close()})
$form.Add_Shown({$form.Activate()});[void]$form.ShowDialog()
