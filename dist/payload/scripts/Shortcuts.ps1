Set-StrictMode -Version Latest

function Get-ShortcutLocations {
  $shell=New-Object -ComObject WScript.Shell
  [pscustomobject]@{
    Desktop=$shell.SpecialFolders.Item('Desktop')
    StartMenu=Join-Path $shell.SpecialFolders.Item('Programs') 'DS_ALGO Local AI'
  }
}

function New-ScriptShortcut([string]$Path,[string]$Script,[string]$Description) {
  $shell=New-Object -ComObject WScript.Shell
  $shortcut=$shell.CreateShortcut($Path)
  $exe=Join-Path $Root (([IO.Path]::GetFileNameWithoutExtension($Script))+'.exe')
  if(Test-Path -LiteralPath $exe){
    $shortcut.TargetPath=[IO.Path]::GetFullPath($exe)
    $shortcut.Arguments=''
  } else {
    $shortcut.TargetPath=(Get-Command powershell.exe).Source
    $shortcut.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
  }
  $shortcut.WorkingDirectory=$Root
  $shortcut.Description=$Description
  $icon=Join-Path $Root 'assets\branding\logo.ico'
  if(Test-Path -LiteralPath $icon){$shortcut.IconLocation="$icon,0"}
  $shortcut.Save()
  $saved=$shell.CreateShortcut($Path)
  if([string]::IsNullOrWhiteSpace([string]$saved.TargetPath)){
    throw "Windows created an invalid shortcut with an empty target: $Path"
  }
}

function Install-LocalAIShortcuts {
  $locations=Get-ShortcutLocations
  New-Item -ItemType Directory -Force -Path $locations.Desktop,$locations.StartMenu|Out-Null
  foreach($obsolete in @('Remove.lnk','Health.lnk')){
    Remove-Item -LiteralPath (Join-Path $locations.StartMenu $obsolete) -Force -ErrorAction SilentlyContinue
  }
  $entries=@(
    @('Install','Install.ps1','Install or resume DS_ALGO Local AI'),
    @('Repair','Repair.ps1','Rebuild DS_ALGO Local AI without starting it'),
    @('Start','Start.ps1','Start DS_ALGO Local AI'),
    @('Stop','Stop.ps1','Stop services and retain containers'),
    @('Uninstall','Uninstall.ps1','Permanently uninstall DS_ALGO Local AI')
  )
  foreach($entry in $entries){
    $script=Join-Path $Root $entry[1]
    New-ScriptShortcut (Join-Path $locations.StartMenu "$($entry[0]).lnk") $script $entry[2]
    if($entry[0] -in @('Install','Repair','Start','Stop')){
      New-ScriptShortcut (Join-Path $locations.Desktop "DS_ALGO Local AI - $($entry[0]).lnk") $script $entry[2]
    }
  }
}

function Register-DSAlgoUninstall {
  $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DSAlgoLocalAISetup'
  New-Item -Path $key -Force | Out-Null
  $uninstall=Join-Path $Root 'uninstall.exe'
  $icon=Join-Path $Root 'assets\branding\logo.ico'
  New-ItemProperty -Path $key -Name DisplayName      -Value 'DSAlgo Local AI Setup'         -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name Publisher         -Value 'Divya Pratap Srivastava'       -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name DisplayVersion    -Value '1.0.0'                         -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name InstallLocation   -Value $Root                           -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name UninstallString   -Value "`"$uninstall`""               -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name QuietUninstallString -Value "`"$uninstall`" -Force"     -PropertyType String -Force | Out-Null
  if (Test-Path -LiteralPath $icon) {
    New-ItemProperty -Path $key -Name DisplayIcon -Value "`"$icon`",0" -PropertyType String -Force | Out-Null
  }
  New-ItemProperty -Path $key -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $key -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
}

function Remove-LocalAIShortcuts {
  $locations=Get-ShortcutLocations
  foreach($name in @('Install','Repair','Start','Stop','Remove','Health','Uninstall')){
    Remove-Item -LiteralPath (Join-Path $locations.Desktop "DS_ALGO Local AI - $name.lnk") -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath (Join-Path $locations.Desktop 'DS_ALGO Local AI - Install.lnk') -Force -ErrorAction SilentlyContinue
  if(Test-Path -LiteralPath $locations.StartMenu){
    Remove-Item -LiteralPath $locations.StartMenu -Recurse -Force
  }
  Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DSAlgoLocalAISetup' -Recurse -Force -ErrorAction SilentlyContinue
}
