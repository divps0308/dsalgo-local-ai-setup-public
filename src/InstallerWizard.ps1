param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  $self=$null
  try{$self=(Get-Process -Id $PID).MainModule.FileName}catch{}
  if(-not$self){$self=$PSCommandPath}
  $elevated=Start-Process -FilePath $self -Verb RunAs -Wait -PassThru
  $elevated.WaitForExit();$elevated.Refresh()
  exit $elevated.ExitCode
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-LicensePath {
  $roots=@()
  if(-not[string]::IsNullOrWhiteSpace($PSScriptRoot)){$roots+=@($PSScriptRoot,(Split-Path -Parent $PSScriptRoot))}
  try{$exeDir=Split-Path -Parent (Get-Process -Id $PID -ErrorAction Stop).MainModule.FileName;if(-not[string]::IsNullOrWhiteSpace($exeDir)){$roots+=@($exeDir,(Split-Path -Parent $exeDir))}}catch{}
  $roots+=$(Get-Location).Path
  foreach($root in @($roots|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}|Select-Object -Unique)){
    foreach($relativePath in @('LICENSE','payload\LICENSE')){
      $candidate=Join-Path $root $relativePath
      if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
    }
  }
  throw 'The canonical LICENSE file could not be found in the packaged installer payload.'
}

function Get-Hardware {
  $ram=0;$cpu='Unknown';$gpu='CPU only';$vram=0
  try{$os=Get-CimInstance Win32_OperatingSystem;$ram=[math]::Round($os.TotalVisibleMemorySize/1MB)}catch{}
  if($ram-le0){try{$computer=Get-CimInstance Win32_ComputerSystem;$ram=[math]::Round([double]$computer.TotalPhysicalMemory/1GB)}catch{}}
  try{$cpu=[string](Get-CimInstance Win32_Processor|Select-Object -First 1).Name}catch{}
  try{
    $smi=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if($smi){
      $line=& $smi.Source '--query-gpu=name,memory.total' '--format=csv,noheader,nounits' 2>$null|Select-Object -First 1
      if($line-match'^\s*(.+?),\s*(\d+)\s*$'){$gpu=$matches[1].Trim();$vram=[math]::Round([double]$matches[2]/1024)}
    }
  }catch{}
  if($gpu-eq'CPU only'){
    try{
      $adapter=Get-CimInstance Win32_VideoController|Where-Object{$_.Name-match'NVIDIA|AMD|Radeon|Intel'-and$_.Name-notmatch'Virtual|Remote|Basic'}|Select-Object -First 1
      if($adapter){$gpu=[string]$adapter.Name;if($adapter.AdapterRAM){$vram=[math]::Round([double]$adapter.AdapterRAM/1GB)}}
    }catch{}
  }
  $cpuCores=1
  try{$cpuCores=[int]((Get-CimInstance Win32_Processor|Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)}catch{}
  [pscustomobject]@{Cpu=$cpu;CpuCores=[math]::Max(1,$cpuCores);RamGiB=$ram;Gpu=$gpu;VramGiB=$vram}
}

function Get-ResourceProfile($hardware){
  $memory=[math]::Max(2,[math]::Floor($hardware.RamGiB*.2))
  $processors=[math]::Max(2,[math]::Floor($hardware.CpuCores*.5))
  $swap=[math]::Min(16,[math]::Max(2,[math]::Ceiling($memory*.5)))
  [ordered]@{dockerMemoryGB=[int]$memory;dockerProcessors=[int]$processors;dockerSwapGB=[int]$swap}
}

function Get-Catalog {
  $root=$PSScriptRoot
  if([string]::IsNullOrWhiteSpace($root)){try{$root=Split-Path -Parent (Get-Process -Id $PID).MainModule.FileName}catch{$root=(Get-Location).Path}}
  $paths=@((Join-Path $root 'payload\config\model-catalog.json'),(Join-Path $root 'config\model-catalog.json'),(Join-Path (Split-Path -Parent $root) 'config\model-catalog.json'))
  foreach($path in $paths){if(Test-Path -LiteralPath $path){return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}}
  throw 'The embedded model catalog could not be found.'
}

function Get-Recommendations($hardware,$useCase,$preferenceMode,$vendor,$country){
  $ramBudget=[math]::Floor($hardware.RamGiB*.8)
  # GPU-backed models may use the full detected dedicated VRAM. Ollama's
  # runtime scheduler manages actual GPU utilization.
  $vramBudget=[math]::Floor($hardware.VramGiB)
  $models=@((Get-Catalog).models)
  $tasks=switch($useCase){'GeneralChat'{@('GeneralChat')}'Reasoning'{@('Reasoning')}'Coding'{@('Coding')}'DeepResearch'{@('DocumentQa','Reasoning')}'All'{@('GeneralChat','Reasoning','Coding','DocumentQa')}default{@('GeneralChat')}}
  $results=@();$supported=@();$unsupported=@()
  foreach($m in $models){
    $taskMatches=@($tasks|Where-Object{$m.tasks-contains$_}).Count
    $hardwareFit=[double]$m.minRamGiB -le $ramBudget -and [double]$m.minVramGiB -le $vramBudget
    $vendorMatch=$vendor-ne'Any'-and$m.organization-eq$vendor;$countryMatch=$country-ne'Any'-and$m.country-eq$country
    $filterFit=$taskMatches -gt 0 -and -not($preferenceMode-eq'Require'-and-not($vendorMatch-or$countryMatch))
    $score=300+($taskMatches*100)+[int]$m.qualityScore
    if($vendorMatch){$vendorBonus=if($preferenceMode-eq'Avoid'){-120}elseif($preferenceMode-eq'Require'){100}else{80};$score+=$vendorBonus}
    if($countryMatch){$countryBonus=if($preferenceMode-eq'Avoid'){-90}elseif($preferenceMode-eq'Require'){100}else{60};$score+=$countryBonus}
    $item=[pscustomobject]@{Id=$m.id;Name=$m.displayName;Tag=$m.ollamaTag;Tasks=@($m.tasks);Score=$score;Ram=$m.minRamGiB;Vram=$m.minVramGiB;Vendor=$m.organization;Country=$m.country;Context=$m.contextTokens;DownloadGiB=[double]$m.downloadGiB;Reason=if(-not$hardwareFit){'Exceeds available RAM or VRAM'}elseif(-not$filterFit){'Filtered by use case or provenance preference'}else{'Supported'};Supported=$hardwareFit}
    if(-not$hardwareFit){$unsupported+=$item}elseif(-not$filterFit){$supported+=$item}else{$results+=$item}
  }
  [pscustomobject]@{Models=@($results|Sort-Object @{Expression='Score';Descending=$true},@{Expression='Vram';Descending=$true},@{Expression='Tag';Descending=$false});SupportedModels=@($supported|Sort-Object displayName);UnsupportedModels=@($unsupported|Sort-Object displayName);RamBudget=[math]::Round($ramBudget,1);VramBudget=[math]::Round($vramBudget,1);UseCase=$useCase}
}

$form=New-Object Windows.Forms.Form
$form.Text='DSAlgo Local AI Setup'
$form.Size=New-Object Drawing.Size(820,600)
$form.StartPosition='CenterScreen'
$form.TopMost=$true
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false

$title=New-Object Windows.Forms.Label
$title.Font=New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold)
$title.Location=New-Object Drawing.Point(24,18);$title.Size=New-Object Drawing.Size(740,38)
$form.Controls.Add($title)
$content=New-Object Windows.Forms.Panel
$content.Location=New-Object Drawing.Point(24,66);$content.Size=New-Object Drawing.Size(750,430)
$form.Controls.Add($content)
$back=New-Object Windows.Forms.Button;$back.Text='Back';$back.Location=New-Object Drawing.Point(520,510);$back.Size=New-Object Drawing.Size(80,32)
$next=New-Object Windows.Forms.Button;$next.Text='Next';$next.Location=New-Object Drawing.Point(610,510);$next.Size=New-Object Drawing.Size(80,32)
$cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancel';$cancel.Location=New-Object Drawing.Point(700,510);$cancel.Size=New-Object Drawing.Size(80,32)
$form.Controls.AddRange(@($back,$next,$cancel))

$page=0;$hardware=$null;$recommendations=$null;$child=$null;$allowWizardClose=$false
$licenseText=New-Object Windows.Forms.TextBox;$licenseText.Multiline=$true;$licenseText.ReadOnly=$true;$licenseText.ScrollBars='Vertical';$licenseText.Size=New-Object Drawing.Size(720,270);$licenseText.Font=New-Object Drawing.Font('Segoe UI',9)
$licenseConfirm=New-Object Windows.Forms.CheckBox;$licenseConfirm.Text='I have read and agree to the LICENSE and the third-party software/model notice.';$licenseConfirm.AutoSize=$true
$installPath=New-Object Windows.Forms.TextBox;$installPath.Text=Join-Path $env:USERPROFILE 'DSAlgo Local AI Setup';$installPath.Width=580
$hardwareText=New-Object Windows.Forms.TextBox;$hardwareText.Multiline=$true;$hardwareText.ReadOnly=$true;$hardwareText.Size=New-Object Drawing.Size(720,260)
$hardwareConfirm=New-Object Windows.Forms.CheckBox;$hardwareConfirm.Text='I have reviewed and confirm this detected hardware information.';$hardwareConfirm.Width=600
$useCase=New-Object Windows.Forms.ComboBox;$useCase.DropDownStyle='DropDownList';[void]$useCase.Items.AddRange(@('General Conversation (Chat)','Reasoning','Coding','Deep Research','All'));$useCase.SelectedIndex=0
$prefMode=New-Object Windows.Forms.ComboBox;$prefMode.DropDownStyle='DropDownList';[void]$prefMode.Items.AddRange(@('None','Prefer','Avoid','Require'));$prefMode.SelectedIndex=0
$vendor=New-Object Windows.Forms.ComboBox;$vendor.DropDownStyle='DropDownList';[void]$vendor.Items.AddRange(@('Any','Alibaba','Cohere','DeepSeek','Google','IBM','Meta','Microsoft','MistralAI','Moonshot','NVIDIA','THUDM'));$vendor.SelectedIndex=0
$country=New-Object Windows.Forms.ComboBox;$country.DropDownStyle='DropDownList';[void]$country.Items.AddRange(@('Any','Canada','China','France','UnitedStates'));$country.SelectedIndex=0
$provenanceNote=New-Object Windows.Forms.Label;$provenanceNote.Size=New-Object Drawing.Size(520,35);$provenanceNote.ForeColor=[Drawing.Color]::DimGray
$recommendGrids=@()
function New-RecommendGrid([bool]$Selectable){
  $grid=New-Object Windows.Forms.DataGridView;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.AllowUserToResizeRows=$false;$grid.RowHeadersVisible=$false;$grid.MultiSelect=$false;$grid.SelectionMode='FullRowSelect';$grid.AutoGenerateColumns=$false;$grid.EditMode='EditOnEnter';$grid.ReadOnly=-not$Selectable;$grid.ScrollBars='Vertical'
  $cols=@(@('Selected','Install',48),@('Model','Model',205),@('General','General chat',72),@('Coding','Coding',55),@('Reasoning','Reasoning',68),@('Documents','Documents',68),@('All','All',38),@('Storage','HDD',62),@('Score','Score',52))
  foreach($c in $cols){$col=if($c[0]-eq'Selected'){New-Object Windows.Forms.DataGridViewCheckBoxColumn}else{New-Object Windows.Forms.DataGridViewTextBoxColumn};$col.Name=$c[0];$col.HeaderText=$c[1];$col.Width=$c[2];$col.ReadOnly=$c[0]-ne'Selected';[void]$grid.Columns.Add($col)}
  return $grid
}
$recommendGrid=New-RecommendGrid $true;$supportedGrid=New-RecommendGrid $true;$unsupportedGrid=New-RecommendGrid $false;$recommendGrids=@($recommendGrid,$supportedGrid,$unsupportedGrid)
$recommendIntro=New-Object Windows.Forms.Label;$recommendIntro.Location=New-Object Drawing.Point(0,0);$recommendIntro.Size=New-Object Drawing.Size(740,24)
$recommendSummary=New-Object Windows.Forms.Label;$recommendSummary.Location=New-Object Drawing.Point(0,344);$recommendSummary.Size=New-Object Drawing.Size(740,58)
$progress=New-Object Windows.Forms.TextBox;$progress.Multiline=$true;$progress.ReadOnly=$true;$progress.ScrollBars='Both';$progress.WordWrap=$false;$progress.Size=New-Object Drawing.Size(720,380);$progress.Font=New-Object Drawing.Font('Consolas',9)

function Add-Row($label,$control,$y){
  $l=New-Object Windows.Forms.Label;$l.Text=$label;$l.Location=New-Object Drawing.Point(5,$y);$l.Size=New-Object Drawing.Size(190,24)
  $control.Location=New-Object Drawing.Point(200,$y);$control.Size=New-Object Drawing.Size(300,25)
  $content.Controls.AddRange(@($l,$control))
}
function Get-SelectedRecommendations {
  $selected=@()
  foreach($grid in @($recommendGrid,$supportedGrid)){foreach($row in $grid.Rows){if([bool]$row.Cells['Selected'].Value){$selected+=$row.Tag}}}
  return @($selected)
}
function Update-RecommendationSummary {
  $selected=@(Get-SelectedRecommendations)
  $storage=0;foreach($model in $selected){$storage+=[double]$model.DownloadGiB}
  $totalStorage=$storage+0.7
  $recommendSummary.Text="$($selected.Count) of 3 models selected. Estimated HDD: $([math]::Round($storage,1)) GiB selected + 0.7 GiB embedding support = $([math]::Round($totalStorage,1)) GiB total.`r`nOnly one conversational model is actively loaded at a time; the other selected models remain stored on disk."
  $next.Enabled=$selected.Count-ge1-and$selected.Count-le3
}
function Add-RecommendationRows($grid,$models,[bool]$Selectable){
  $grid.Rows.Clear();foreach($m in @($models)){$general=if($m.Tasks-contains'GeneralChat'){'Yes'}else{''};$coding=if($m.Tasks-contains'Coding'){'Yes'}else{''};$reasoning=if($m.Tasks-contains'Reasoning'){'Yes'}else{''};$documents=if($m.Tasks-contains'DocumentQa'){'Yes'}else{''};$all=if($general-and$coding-and$reasoning-and$documents){'Yes'}else{''};$row=$grid.Rows.Add($false,"$($m.Name)`r`n$($m.Tag)",$general,$coding,$reasoning,$documents,$all,"$($m.DownloadGiB) GiB",$m.Score);$grid.Rows[$row].Tag=$m;$grid.Rows[$row].Height=34;$grid.Rows[$row].Cells['Model'].ToolTipText="$($m.Reason)`nMinimum RAM: $($m.Ram) GiB`nMinimum VRAM: $($m.Vram) GiB";if(-not$Selectable){$grid.Rows[$row].Cells['Selected'].Value=$false}}
}
function Show-Page {
  $content.Controls.Clear();$back.Enabled=$page-gt0;$next.Enabled=$true;$next.Text='Next'
  switch($page){
    0{
      $title.Text='License and third-party components'
      $licenseContent=Get-Content -LiteralPath (Get-LicensePath) -Raw -ErrorAction Stop
      $licenseContent=$licenseContent -replace "`r`n|`n|`r","`r`n"
      $licenseText.Text=$licenseContent.TrimEnd()+"`r`n`r`nTHIRD-PARTY SOFTWARE AND MODELS`r`n`r`nThis distribution may install or invoke open-source software, container images, services, and AI models. Those components remain the property of their respective authors and licensors and are governed by their own licenses and terms. DSAlgo Local AI Setup claims no ownership of them and makes no responsibility or warranty claim for third-party behavior. They are provided for lawful, user-directed use, including fair-use purposes where applicable. Review the applicable licenses and terms before continuing."
      $licenseText.Location=New-Object Drawing.Point(5,5);$licenseConfirm.Location=New-Object Drawing.Point(5,285)
      $content.Controls.AddRange(@($licenseText,$licenseConfirm));$next.Enabled=$licenseConfirm.Checked
    }
    1{$title.Text='Choose installation location';Add-Row 'Installation folder' $installPath 30}
    2{
      $title.Text='Review detected hardware'
      if(-not$script:hardware){$script:hardware=Get-Hardware}
      $hardwareText.Text="CPU: $($script:hardware.Cpu)`r`nInstalled RAM: $($script:hardware.RamGiB).0 GiB`r`nGPU: $($script:hardware.Gpu)`r`nDedicated VRAM: $($script:hardware.VramGiB).0 GiB"
      $hardwareText.Location=New-Object Drawing.Point(5,15);$hardwareConfirm.Location=New-Object Drawing.Point(5,300)
      $content.Controls.AddRange(@($hardwareText,$hardwareConfirm))
    }
    3{
      $title.Text='Select model preferences'
      Add-Row 'Primary use case' $useCase 5
      $runtimeLabel=New-Object Windows.Forms.Label;$runtimeLabel.Text='Runtime';$runtimeLabel.Location=New-Object Drawing.Point(5,100);$runtimeLabel.Size=New-Object Drawing.Size(190,24)
      $runtimeValue=New-Object Windows.Forms.Label;$runtimeValue.Text='Ollama (local)';$runtimeValue.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$runtimeValue.Location=New-Object Drawing.Point(200,100);$runtimeValue.Size=New-Object Drawing.Size(300,24)
      $runtimeHelp=New-Object Windows.Forms.Label;$runtimeHelp.Text='Recommendations are generated for local Ollama models only.';$runtimeHelp.Location=New-Object Drawing.Point(200,124);$runtimeHelp.Size=New-Object Drawing.Size(480,24);$runtimeHelp.ForeColor=[Drawing.Color]::DimGray
      $content.Controls.AddRange(@($runtimeLabel,$runtimeValue,$runtimeHelp))
      Add-Row 'Model provenance mode' $prefMode 160;Add-Row 'Preferred organization' $vendor 205;Add-Row 'Preferred country/region' $country 250
      $provenanceNote.Location=New-Object Drawing.Point(200,280);$content.Controls.Add($provenanceNote)
      $note=New-Object Windows.Forms.Label;$note.Text='The installer allocates approximately 20% of detected RAM and 50% of logical processors to WSL/Docker. GPU model recommendations may use up to 100% of detected dedicated VRAM; Ollama manages runtime GPU utilization.';$note.Location=New-Object Drawing.Point(5,315);$note.Size=New-Object Drawing.Size(700,42);$note.AutoSize=$false;$content.Controls.Add($note)
    }
    4{
      $title.Text='Review model recommendations'
      $useCaseValue=@{'General Conversation (Chat)'='GeneralChat';'Reasoning'='Reasoning';'Coding'='Coding';'Deep Research'='DeepResearch';'All'='All'}[[string]$useCase.SelectedItem]
      $script:recommendations=Get-Recommendations $script:hardware $useCaseValue ([string]$prefMode.SelectedItem) ([string]$vendor.SelectedItem) ([string]$country.SelectedItem)
      $recommendIntro.Text="RAM budget: $($script:recommendations.RamBudget) GiB   |   VRAM budget: $($script:recommendations.VramBudget) GiB   |   Select 1 to 3 models from the first two categories."
      $groups=@(@('Recommended models',$recommendGrid,$script:recommendations.Models,$true),@('Supported but not recommended / filtered out',$supportedGrid,$script:recommendations.SupportedModels,$true),@('Unsupported models',$unsupportedGrid,$script:recommendations.UnsupportedModels,$false));$y=28
      foreach($g in $groups){$count=@($g[2]).Count;$cue=if($count-gt2){' — scroll to view all'}else{''};$label=New-Object Windows.Forms.Label;$label.Text="$($g[0]) ($count)$cue";$label.Location=New-Object Drawing.Point -ArgumentList 0,$y;$label.Size=New-Object Drawing.Size -ArgumentList 740,20;$grid=$g[1];$grid.Location=New-Object Drawing.Point -ArgumentList 0,($y+20);$grid.Size=New-Object Drawing.Size -ArgumentList 750,95;Add-RecommendationRows $grid $g[2] $g[3];$content.Controls.AddRange(@($label,$grid));$y+=122}
      $recommendSummary.Location=New-Object Drawing.Point(0,398);$content.Controls.AddRange(@($recommendIntro,$recommendSummary));$next.Text='Install';Update-RecommendationSummary
    }
    5{$title.Text='Installing DSAlgo Local AI Setup';$content.Controls.Add($progress);$back.Enabled=$false;$next.Enabled=$false}
    6{$title.Text='Installation complete';$done=New-Object Windows.Forms.Label;$done.Text='The setup was installed successfully and is currently stopped. Use Start from the Desktop or Start Menu.';$done.Location=New-Object Drawing.Point(10,30);$done.Size=New-Object Drawing.Size(700,80);$content.Controls.Add($done);$back.Enabled=$false;$next.Text='Finish'}
  }
  $form.BringToFront();$form.Activate()
}
function Append-Progress([string]$text){
  if([string]::IsNullOrEmpty($text)){return}
  if($text-match'^(?:Phase: complete|Installation is complete)'){$script:installerSawComplete=$true}
  if($text-match'Windows must restart'){$script:installerSawRestartRequired=$true}
  if($progress.InvokeRequired){$progress.BeginInvoke([Action[string]]{param($s)$progress.AppendText($s+"`r`n");$progress.SelectionStart=$progress.TextLength;$progress.ScrollToCaret()},$text)|Out-Null}else{$progress.AppendText($text+"`r`n")}
}
function Read-NewInstallerOutput([string]$Path,[string]$Kind){
  if(-not(Test-Path -LiteralPath $Path)){return}
  try{[string]$text=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop}catch{return}
  if([string]::IsNullOrEmpty($text)){return}
  $offset=if($Kind-eq'error'){$script:installerErrorOffset}else{$script:installerOutputOffset}
  if($text.Length-le$offset){return}
  $newText=$text.Substring($offset)
  if($Kind-eq'error'){$script:installerErrorOffset=$text.Length}else{$script:installerOutputOffset=$text.Length}
  foreach($line in ($newText -split "`r?`n")){
    if(-not[string]::IsNullOrWhiteSpace($line)){
      $display=if($Kind-eq'error'){'ERROR: '+$line}else{$line}
      Append-Progress $display
    }
  }
}
function Start-Installation {
  $target=[IO.Path]::GetFullPath($installPath.Text)
  $releaseRoot=$PSScriptRoot;if([string]::IsNullOrWhiteSpace($releaseRoot)){try{$releaseRoot=Split-Path -Parent (Get-Process -Id $PID).MainModule.FileName}catch{$releaseRoot=(Get-Location).Path}}
  $exeRoot=$releaseRoot
  $payload=Join-Path $releaseRoot 'payload';if(Test-Path (Join-Path $payload 'Install.ps1')){$releaseRoot=$payload}
  New-Item -ItemType Directory -Force -Path $target|Out-Null
  Append-Progress "Copying payload to $target"
  Get-ChildItem $releaseRoot -Force|Where-Object{$_.Name-notin@('.git','dist','artifacts','.env','runtime','backups','node_modules','.pnpm-store')}|ForEach-Object{Copy-Item $_.FullName $target -Recurse -Force}
  Get-ChildItem $exeRoot -Filter '*.exe' -File -ErrorAction SilentlyContinue|ForEach-Object{Copy-Item $_.FullName $target -Force}
  $chosen=@(Get-SelectedRecommendations)
  $tags=@($chosen|ForEach-Object{$_.Tag})+@('embeddinggemma:latest')
  [ordered]@{tags=$tags}|ConvertTo-Json|Set-Content (Join-Path $target 'config\selected-models.json') -Encoding UTF8
  $general=@($chosen|Where-Object{$_.Tasks-contains'GeneralChat'}|Select-Object -First 1);if(-not$general){$general=@($chosen|Select-Object -First 1)}
  $coder=@($chosen|Where-Object{$_.Tasks-contains'Coding'}|Select-Object -First 1);if(-not$coder){$coder=$general}
  $reasoning=@($chosen|Where-Object{$_.Tasks-contains'Reasoning'}|Select-Object -First 1);if(-not$reasoning){$reasoning=$general}
  $resourceProfile=Get-ResourceProfile $script:hardware
  $reservedRam=[math]::Floor($script:hardware.RamGiB*.2)
  $modelConfig=[ordered]@{schemaVersion=1;hardwareProfile=[ordered]@{gpu=$script:hardware.Gpu;vramMB=([int]$script:hardware.VramGiB*1024);systemRamGB=$script:hardware.RamGiB;reservedSystemRamGB=$reservedRam;notes='Generated deterministically by install.exe.'};models=[ordered]@{
    general=[ordered]@{ollamaTag=$general[0].Tag;displayName=$general[0].Name;role='general/tool agent';numCtx=[math]::Min(16384,[int]$general[0].Context);temperature=.55;keepAlive='5m';toolCalling=$true}
    coder=[ordered]@{ollamaTag=$coder[0].Tag;displayName=$coder[0].Name;role='coding/tool agent';numCtx=[math]::Min(16384,[int]$coder[0].Context);temperature=.2;keepAlive='10m';toolCalling=$true}
    reasoning=[ordered]@{ollamaTag=$reasoning[0].Tag;displayName=$reasoning[0].Name;role='reasoning/research agent';numCtx=[math]::Min(16384,[int]$reasoning[0].Context);temperature=.35;keepAlive='3m';toolCalling=$false}
    embedding=[ordered]@{ollamaTag='embeddinggemma:latest';displayName='EmbeddingGemma';role='embeddings';numCtx=2048;temperature=0;keepAlive='5m';toolCalling=$false}
  };profiles=[ordered]@{core=[ordered]@{dockerMemoryGB=$resourceProfile.dockerMemoryGB;dockerProcessors=$resourceProfile.dockerProcessors;dockerSwapGB=$resourceProfile.dockerSwapGB;default=$true}}}
  $modelConfig|ConvertTo-Json -Depth 8|Set-Content (Join-Path $target 'config\models.json') -Encoding UTF8
  $agents=[ordered]@{mcpServers=@();agents=@(
    [ordered]@{id='sample-general';name='Sample General Conversation Agent';source='setup';modelRole='general';modelTag=$general[0].Tag;maxSteps=6;instructions='Provide helpful, accurate general conversation and everyday assistance.';enabled=$true;builtinTools=@('calculate','get_datetime');mcpServers=@()},
    [ordered]@{id='sample-coding';name='Sample Coding Agent';source='setup';modelRole='coder';modelTag=$coder[0].Tag;maxSteps=8;instructions='Help with local software development, debugging, tests, and code review.';enabled=$true;builtinTools=@('workspace_list','workspace_read','workspace_search','workspace_write','run_command');mcpServers=@()},
    [ordered]@{id='sample-research';name='Sample Deep Research Agent';source='setup';modelRole='reasoning';modelTag=$reasoning[0].Tag;maxSteps=8;instructions='Analyze supplied local sources carefully, compare evidence, and report uncertainty.';enabled=$true;builtinTools=@('workspace_list','workspace_read','workspace_search');mcpServers=@()}
  )}
  $agents|ConvertTo-Json -Depth 8|Set-Content (Join-Path $target 'config\agents.json') -Encoding UTF8
  $runtime=Join-Path $target 'runtime';New-Item -ItemType Directory -Force -Path $runtime|Out-Null
  $script:installerOutputLog=Join-Path $runtime 'installer-child.stdout.log'
  $script:installerErrorLog=Join-Path $runtime 'installer-child.stderr.log'
  Set-Content -LiteralPath $script:installerOutputLog -Value '' -Encoding UTF8
  Set-Content -LiteralPath $script:installerErrorLog -Value '' -Encoding UTF8
  $script:installerOutputOffset=0;$script:installerErrorOffset=0;$script:installerSawComplete=$false;$script:installerSawRestartRequired=$false
  $powershell=(Get-Command powershell.exe -ErrorAction Stop).Source
  $installScript=Join-Path $target 'Install.ps1'
  try{
    $script:child=Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"'-f$installScript)) -WorkingDirectory $target -PassThru -WindowStyle Hidden -RedirectStandardOutput $script:installerOutputLog -RedirectStandardError $script:installerErrorLog
    Append-Progress "Installer process started (PID $($script:child.Id)). Live output is also saved to runtime\\installer-child.stdout.log and runtime\\installer-child.stderr.log."
    $installMonitor.Start()
  }catch{
    Append-Progress "ERROR: Could not start the deployed installer: $($_.Exception.Message)"
    $next.Enabled=$false;$cancel.Text='Close'
  }
}

$back.Add_Click({if($script:page-gt0){$script:page--;Show-Page}})
$licenseConfirm.Add_CheckedChanged({if($script:page -eq 0){$next.Enabled=$licenseConfirm.Checked}})
$next.Add_Click({
  if($script:page-eq0-and-not$licenseConfirm.Checked){[Windows.Forms.MessageBox]::Show($form,'You must read and accept the LICENSE before continuing.');return}
  if($script:page-eq1-and[string]::IsNullOrWhiteSpace($installPath.Text)){[Windows.Forms.MessageBox]::Show($form,'Choose an installation folder.');return}
  if($script:page-eq2-and-not$hardwareConfirm.Checked){[Windows.Forms.MessageBox]::Show($form,'Review and confirm the detected hardware before continuing.');return}
  if($script:page-eq3-and$prefMode.SelectedItem-eq'Require'-and$vendor.SelectedItem-eq'Any'-and$country.SelectedItem-eq'Any'){[Windows.Forms.MessageBox]::Show($form,'Select an organization, country, or both when Require is selected.');return}
  if($script:page-eq4){
    $selectedForInstall=@(Get-SelectedRecommendations)
    if($selectedForInstall.Count-lt1){[Windows.Forms.MessageBox]::Show($form,'Select at least one model to install.');return}
    if($selectedForInstall.Count-gt3){[Windows.Forms.MessageBox]::Show($form,'Select no more than three models to install.');return}
    $script:page=5;Show-Page
    try{Start-Installation}catch{
      Append-Progress "ERROR: The installer could not prepare the selected configuration: $($_.Exception.Message)"
      $next.Enabled=$false;$cancel.Text='Close'
    }
    return
  }
  if($script:page-eq6){$form.Close();return}
  $script:page++;Show-Page
})
$prefMode.Add_SelectedIndexChanged({
  $enabled=$prefMode.SelectedItem-ne'None'
  $vendor.Enabled=$enabled;$country.Enabled=$enabled
  if(-not$enabled){$vendor.SelectedIndex=0;$country.SelectedIndex=0;$provenanceNote.Text='Choose Prefer, Avoid, or Require to enable provenance filters.'}
  elseif($vendor.SelectedItem-eq'Any'-and$country.SelectedItem-eq'Any'){$provenanceNote.Text='Choose an organization or country for this preference to affect ranking.'}
  else{$provenanceNote.Text=''}
})
$vendor.Add_SelectedIndexChanged({if($prefMode.SelectedItem-ne'None'){$provenanceNote.Text=if($vendor.SelectedItem-eq'Any'-and$country.SelectedItem-eq'Any'){'Choose an organization or country for this preference to affect ranking.'}else{''}}})
$country.Add_SelectedIndexChanged({if($prefMode.SelectedItem-ne'None'){$provenanceNote.Text=if($vendor.SelectedItem-eq'Any'-and$country.SelectedItem-eq'Any'){'Choose an organization or country for this preference to affect ranking.'}else{''}}})
$selectableGrids=@($recommendGrid,$supportedGrid)
foreach($selectionGrid in $selectableGrids){$selectionGrid.Add_CellBeginEdit({
  param($sender,$eventArgs)
  if($eventArgs.RowIndex-lt0-or$eventArgs.ColumnIndex-ne$sender.Columns['Selected'].Index){return}
  $current=[bool]$sender.Rows[$eventArgs.RowIndex].Cells['Selected'].Value
  if(-not$current-and@(Get-SelectedRecommendations).Count-ge3){
    $eventArgs.Cancel=$true
    [Windows.Forms.MessageBox]::Show($form,'You can install at most three conversational models.','Selection limit')|Out-Null
  }
});$selectionGrid.Add_CurrentCellDirtyStateChanged({param($sender,$eventArgs) if($sender.IsCurrentCellDirty){$sender.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)|Out-Null}});$selectionGrid.Add_CellValueChanged({
  param($sender,$eventArgs)
  if($eventArgs.RowIndex-lt0-or$eventArgs.ColumnIndex-ne$sender.Columns['Selected'].Index){return}
  $selected=@(Get-SelectedRecommendations)
  if($selected.Count-gt3){
    $sender.Rows[$eventArgs.RowIndex].Cells['Selected'].Value=$false
    $sender.InvalidateRow($eventArgs.RowIndex)
  }
  Update-RecommendationSummary
})}
$form.Add_FormClosing({
  param($sender,$eventArgs)
  if(-not$script:allowWizardClose-and$script:child-and-not$script:child.HasExited){
    $eventArgs.Cancel=$true
    $form.TopMost=$true;$form.WindowState=[Windows.Forms.FormWindowState]::Normal;$form.BringToFront();$form.Activate()
    [Windows.Forms.MessageBox]::Show($form,'Installation is still running. Use Cancel and confirm cancellation if you want to stop it.','DSAlgo Local AI Setup')|Out-Null
  }
})
$form.Add_Shown({$form.BringToFront();$form.Activate();$form.TopMost=$false})
$installMonitor=New-Object Windows.Forms.Timer;$installMonitor.Interval=500
$installMonitor.Add_Tick({
  try{
    if(-not$script:child){return}
    Read-NewInstallerOutput $script:installerOutputLog 'output'
    Read-NewInstallerOutput $script:installerErrorLog 'error'
    if(-not$script:child.HasExited){return}
    $installMonitor.Stop()
    Read-NewInstallerOutput $script:installerOutputLog 'output'
    Read-NewInstallerOutput $script:installerErrorLog 'error'
    $script:installerExitCode=$script:child.ExitCode
    $hasExitCode=-not[string]::IsNullOrWhiteSpace([string]$script:installerExitCode)
    # PS2EXE can expose no exit code even after the child writes its terminal
    # phase. The explicit phase is the authoritative success signal in that case.
    if ($script:installerSawRestartRequired) {
      Append-Progress 'Windows restart required. Restart Windows, then run Install.exe from the installed folder to resume installation.'
      $next.Enabled=$false;$cancel.Text='Close'
    }elseif ($script:installerSawComplete -and ((-not $hasExitCode) -or $script:installerExitCode -eq 0)) {
      $script:page=6;Show-Page
    }else{
      $exitDescription=if($hasExitCode){[string]$script:installerExitCode}else{'unavailable'}
      Append-Progress "Installation failed with exit code $exitDescription. Review runtime\\installer-child.stderr.log for the full error."
      $next.Enabled=$false;$cancel.Text='Close'
    }
  }catch{
    $installMonitor.Stop()
    Append-Progress "ERROR: Installer progress monitor stopped: $($_.Exception.Message)"
    $next.Enabled=$false;$cancel.Text='Close'
  }
})
$vendor.Enabled=$false;$country.Enabled=$false;$provenanceNote.Text='Choose Prefer, Avoid, or Require to enable provenance filters.'
$cancel.Add_Click({if($script:child-and-not$script:child.HasExited){$answer=[Windows.Forms.MessageBox]::Show($form,'Cancel the running installation?','Confirm',[Windows.Forms.MessageBoxButtons]::YesNo);if($answer-ne[Windows.Forms.DialogResult]::Yes){return};try{$script:child.Kill()}catch{}};$script:allowWizardClose=$true;$installMonitor.Stop();$form.Close()})

Show-Page
[void]$form.ShowDialog()
