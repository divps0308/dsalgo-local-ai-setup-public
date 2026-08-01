param([ValidateSet('Start','Stop','Repair','Remove','Uninstall')][string]$Operation)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$form=New-Object Windows.Forms.Form; $form.Text="DSAlgo Local AI Setup - $Operation"; $form.Size=New-Object Drawing.Size(820,560); $form.StartPosition='CenterScreen'; $form.TopMost=$true
$title=New-Object Windows.Forms.Label; $title.Text="$Operation DSAlgo Local AI Setup"; $title.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold); $title.Location=New-Object Drawing.Point(24,18); $title.Size=New-Object Drawing.Size(740,35); $form.Controls.Add($title)
$output=New-Object Windows.Forms.TextBox; $output.Multiline=$true; $output.ReadOnly=$true; $output.ScrollBars='Both'; $output.Location=New-Object Drawing.Point(24,70); $output.Size=New-Object Drawing.Size(755,380); $output.Font=New-Object Drawing.Font('Consolas',9); $form.Controls.Add($output)
$next=New-Object Windows.Forms.Button; $next.Text='Next'; $next.Location=New-Object Drawing.Point(570,475); $next.Size=New-Object Drawing.Size(95,30); $form.Controls.Add($next)
$cancel=New-Object Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Location=New-Object Drawing.Point(680,475); $cancel.Size=New-Object Drawing.Size(95,30); $form.Controls.Add($cancel)
$script:child=$null; $script:started=$false; $script:completedAt=$null
function Append([string]$s){if($s){$output.AppendText($s.TrimEnd()+[Environment]::NewLine);$output.SelectionStart=$output.TextLength;$output.ScrollToCaret()}}
function Update-WizardProgress {
  if(Test-Path -LiteralPath $script:out){ Append (Get-Content -LiteralPath $script:out -Raw) }
  if(Test-Path -LiteralPath $script:err){ Append (Get-Content -LiteralPath $script:err -Raw) }
  if($script:child -and $script:child.HasExited){
    $script:timer.Stop(); $script:child.Refresh()
    Append ("Completed with exit code {0}" -f $script:child.ExitCode)
    $cancel.Enabled=$false; $next.Text='Close'; $next.Enabled=$true
    $script:completedAt=Get-Date
    $next.Add_Click({$form.Close()})
  }
  if($script:completedAt -and ((Get-Date)-$script:completedAt).TotalSeconds -ge 2){$form.Close()}
}
$next.Add_Click({
  if($script:started){return}
  $script:started=$true; $next.Enabled=$false
  Append "Starting $Operation..."
  $script:out=Join-Path $root ("runtime\wizard-{0}.stdout.log" -f $Operation)
  $script:err=Join-Path $root ("runtime\wizard-{0}.stderr.log" -f $Operation)
  New-Item -ItemType Directory -Force -Path (Split-Path $script:out) | Out-Null
  $scriptPath=Join-Path $root ($Operation+'.ps1')
  # Start-Process flattens ArgumentList; quote paths containing spaces so
  # PowerShell receives the complete -File value.
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$scriptPath+'"'),'-WizardChild')
  if($Operation -in @('Remove','Uninstall')){$args+='-Force'}
  $script:child=Start-Process powershell.exe -ArgumentList $args -WorkingDirectory $root -PassThru -RedirectStandardOutput $script:out -RedirectStandardError $script:err
  $script:timer=New-Object Windows.Forms.Timer; $script:timer.Interval=400
  $script:timer.Add_Tick({Update-WizardProgress}); $script:timer.Start()
})
$cancel.Add_Click({if($script:child -and -not $script:child.HasExited){Stop-Process -Id $script:child.Id -Force -ErrorAction SilentlyContinue};$form.Close()})
$form.Add_Shown({$form.Activate()});[void]$form.ShowDialog()
