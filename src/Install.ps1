param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $self = $null
    try { $self = (Get-Process -Id $PID -ErrorAction Stop).MainModule.FileName } catch { }
    if (-not $self) { $self = $PSCommandPath }
    if (-not $self) { $self = (Get-Command powershell.exe).Source }
    $elevatedArgs = if ([IO.Path]::GetExtension($self) -eq '.exe') { @() } else { @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$PSCommandPath`"") }
    if (@($elevatedArgs).Count -eq 0) {
        $elevated = Start-Process -FilePath $self -Verb RunAs -Wait -PassThru
    } else {
        $elevated = Start-Process -FilePath $self -Verb RunAs -ArgumentList $elevatedArgs -Wait -PassThru
    }
    if ($elevated) { exit $elevated.ExitCode }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-DeterministicModelRecommendations {
    param([ValidateSet('General','Coding','Research')][string]$UseCase='General')
    $catalogRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($catalogRoot)) { $catalogRoot = (Get-Location).Path }
    $catalogPath = Join-Path $catalogRoot 'config\model-catalog.json'
    $ramGiB=0; try{$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;$ramGiB=[math]::Round($os.TotalVisibleMemorySize/1MB)}catch{}
    $vramGiB=0;$gpuName='CPU only';try{$smi=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue;if($smi){$line=(& $smi.Source '--query-gpu=name,memory.total' '--format=csv,noheader,nounits' 2>$null|Select-Object -First 1);if($line -match '^\s*(.+?),\s*(\d+)\s*$'){$gpuName=$matches[1].Trim();$vramGiB=[math]::Round([double]$matches[2]/1024)}};if($gpuName -eq 'CPU only'){$gpu=Get-CimInstance Win32_VideoController|Where-Object{$_.Name -match 'NVIDIA|AMD|Radeon|Intel' -and $_.Name -notmatch 'Virtual|Remote|Basic Display'}|Sort-Object @{Expression={if($_.Name -match 'NVIDIA'){0}else{1}}}|Select-Object -First 1;if($gpu){$gpuName=[string]$gpu.Name;if($gpu.AdapterRAM){$vramGiB=[math]::Round([double]$gpu.AdapterRAM/1GB)}}}}catch{}
    if (Test-Path -LiteralPath $catalogPath) { $catalog=Get-Content -LiteralPath $catalogPath -Raw|ConvertFrom-Json } else {
        $catalog=[pscustomobject]@{models=@(
            [pscustomobject]@{id='qwen2.5-coder-7b';displayName='Qwen 2.5 Coder 7B';tasks=@('Coding','General');minRamGiB=16;minVramGiB=6;ollamaTag='qwen2.5-coder:7b'},
            [pscustomobject]@{id='llama3.1-8b';displayName='Llama 3.1 8B';tasks=@('General','Research');minRamGiB=16;minVramGiB=6;ollamaTag='llama3.1:8b'},
            [pscustomobject]@{id='deepseek-r1-14b';displayName='DeepSeek R1 14B';tasks=@('Research');minRamGiB=24;minVramGiB=10;ollamaTag='deepseek-r1:14b'}
        )}
    }
    $models=@($catalog.models)|Where-Object{$_.tasks -contains $UseCase -and $_.minRamGiB -le $ramGiB -and $_.minVramGiB -le $vramGiB}
    if(@($models).Count -eq 0){$models=@($catalog.models)|Where-Object{$_.minRamGiB -le $ramGiB -and $_.minVramGiB -le $vramGiB}}
    $recommendations=@($models|Sort-Object minVramGiB,id|ForEach-Object{[ordered]@{id=$_.id;displayName=$_.displayName;ollamaTag=$_.ollamaTag}})
    [ordered]@{status=if($recommendations.Count){'success'}else{'no_viable_local_llm'};hardware=[ordered]@{ramGiB=$ramGiB;vramGiB=$vramGiB;gpu=$gpuName};recommendations=$recommendations}
}

$defaultRoot = Join-Path $env:USERPROFILE 'DSAlgo Local AI Setup'
$form = New-Object Windows.Forms.Form
$form.Text = 'DSAlgo Local AI Setup'
$form.Width = 620
$form.Height = 220
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Add_Shown({ $form.BringToFront(); $form.Activate(); $form.TopMost = $false })

$label = New-Object Windows.Forms.Label
$label.Text = 'Installation folder:'
$label.Left = 20; $label.Top = 25; $label.Width = 150
$form.Controls.Add($label)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Left = 20; $pathBox.Top = 52; $pathBox.Width = 460
$pathBox.Text = $defaultRoot
$form.Controls.Add($pathBox)

$browse = New-Object Windows.Forms.Button
$browse.Text = 'Browse...'; $browse.Left = 490; $browse.Top = 50; $browse.Width = 90
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $pathBox.Text
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) { $pathBox.Text = $dialog.SelectedPath }
})
$form.Controls.Add($browse)

$install = New-Object Windows.Forms.Button
$install.Text = 'Install'; $install.Left = 390; $install.Top = 110; $install.Width = 90
$install.Add_Click({
    if ([string]::IsNullOrWhiteSpace($pathBox.Text)) { [Windows.Forms.MessageBox]::Show($form,'Choose an installation folder.'); return }
    $form.Tag = [pscustomobject]@{ Path = $pathBox.Text; UseCase = [string]$useCase.SelectedItem }
    $form.DialogResult = [Windows.Forms.DialogResult]::OK
    $form.Hide()
})
$form.Controls.Add($install)

$cancel = New-Object Windows.Forms.Button
$cancel.Text = 'Cancel'; $cancel.Left = 490; $cancel.Top = 110; $cancel.Width = 90
$cancel.Add_Click({ $form.DialogResult = [Windows.Forms.DialogResult]::Cancel; $form.Close() })
$form.Controls.Add($cancel)

$useCase = New-Object Windows.Forms.ComboBox
$useCase.Left = 20; $useCase.Top = 90; $useCase.Width = 220
$useCase.DropDownStyle = 'DropDownList'
[void]$useCase.Items.AddRange(@('General','Coding','Research'))
$useCase.SelectedIndex = 0
$form.Controls.Add($useCase)

if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 1 }

$selection = $form.Tag
$recommendation = Get-DeterministicModelRecommendations -UseCase $selection.UseCase
$summary = ($recommendation.recommendations | ForEach-Object { "$($_.displayName) [$($_.ollamaTag)]" }) -join "`r`n"
if ([string]::IsNullOrWhiteSpace($summary)) { $summary = 'No catalog model met the detected hardware constraints.' }
$confirm = [Windows.Forms.MessageBox]::Show($form, "Detected hardware:`r`n$($recommendation.hardware.gpu), $($recommendation.hardware.ramGiB) GiB RAM, $($recommendation.hardware.vramGiB) GiB VRAM`r`n`r`nRecommended models:`r`n$summary`r`n`r`nContinue installation?", 'Model recommendations', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Information)
if ($confirm -ne [Windows.Forms.DialogResult]::Yes) { exit 1 }
$selectedTags = @($recommendation.recommendations | Select-Object -First 3 | ForEach-Object { $_.ollamaTag })

# The release executable is intentionally repository-relative. The production
# installer implementation will copy the selected core payload and generated
# configuration into this destination before launching the lifecycle executables.
$sourceRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
    try { $sourceRoot = Split-Path -Parent (Get-Process -Id $PID -ErrorAction Stop).MainModule.FileName } catch { $sourceRoot = (Get-Location).Path }
}
$bundledPayload = Join-Path $sourceRoot 'payload'
if (Test-Path -LiteralPath (Join-Path $bundledPayload 'Install.ps1')) { $sourceRoot = $bundledPayload }
$targetRoot = [IO.Path]::GetFullPath([string]$selection.Path)
if (-not (Test-Path -LiteralPath $targetRoot)) { New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null }
$bootstrapLog = Join-Path $targetRoot 'installer-bootstrap.log'
"$(Get-Date -Format s) sourceRoot=$sourceRoot targetRoot=$targetRoot" | Set-Content -LiteralPath $bootstrapLog -Encoding UTF8
$driveLetter = [IO.Path]::GetPathRoot($targetRoot).TrimEnd('\')
$freeBytes = $null
$drive = Get-PSDrive -Name $driveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
if ($drive) { $freeBytes = [int64]$drive.Free }
if ($null -eq $freeBytes) {
    try { $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveLetter'" -ErrorAction Stop; $freeBytes = [int64]$disk.FreeSpace } catch { }
}
if ($null -ne $freeBytes -and $freeBytes -lt 30GB) { throw "At least 30 GiB of free space is required on $driveLetter before installation." }
if ($null -eq $freeBytes) { [Windows.Forms.MessageBox]::Show($form,"Unable to verify free space on $driveLetter. Installation will continue only after you confirm.", 'Disk check warning', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning) | Out-Null }

Get-ChildItem -LiteralPath $sourceRoot -Force |
    Where-Object { $_.Name -notin @('.git','dist','artifacts','.env','runtime','backups','node_modules','.pnpm-store') } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $targetRoot -Recurse -Force }
if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'Install.ps1'))) { throw "Installer payload is incomplete; Install.ps1 was not copied. See $bootstrapLog" }
Get-ChildItem -LiteralPath (Join-Path $targetRoot 'config') -Filter 'personal-*' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $targetRoot 'config\secrets.dpapi.json') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $targetRoot 'config\oauth-tokens.dpapi.json') -Force -ErrorAction SilentlyContinue
$selectionFile = Join-Path $targetRoot 'config\selected-models.json'
[ordered]@{ tags = @($selectedTags) } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $selectionFile -Encoding UTF8
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'dist')) {
    Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'dist') -Filter '*.exe' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $targetRoot -Force }
}
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$installScript = Join-Path $targetRoot 'Install.ps1'
$logPath = Join-Path $targetRoot 'runtime\installer-child.log'
$errorLogPath = Join-Path $targetRoot 'runtime\installer-child-error.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
$childArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installScript)
$childOutput = & $powershell @childArgs 2>&1
$childExitCode = $LASTEXITCODE
($childOutput | Out-String) | Set-Content -LiteralPath $logPath -Encoding UTF8
if ($childExitCode -ne 0) {
    "Child process exit code: $childExitCode" | Set-Content -LiteralPath $errorLogPath -Encoding UTF8
    $details = @($logPath,$errorLogPath) | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Content -LiteralPath $_ -Raw } | Out-String
    throw "The deployed setup failed with exit code $childExitCode.`r`n$details"
}
[Windows.Forms.MessageBox]::Show($form, 'Installation completed successfully. Services are installed and currently stopped. Use Start from the Desktop or Start Menu when ready.', 'DSAlgo Local AI Setup', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
$form.Close()
