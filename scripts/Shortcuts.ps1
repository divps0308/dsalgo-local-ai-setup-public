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
  $shortcut.TargetPath=(Get-Command powershell.exe).Source
  $shortcut.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$Script`""
  $shortcut.WorkingDirectory=$Root
  $shortcut.Description=$Description
  $icon=Join-Path $Root 'assets\branding\logo.ico'
  if(Test-Path -LiteralPath $icon){$shortcut.IconLocation="$icon,0"}
  $shortcut.Save()
}

function Install-LocalAIShortcuts {
  $locations=Get-ShortcutLocations
  New-Item -ItemType Directory -Force -Path $locations.Desktop,$locations.StartMenu|Out-Null
  $entries=@(
    @('Install','Install.ps1','Install or resume DS_ALGO Local AI'),
    @('Repair','Repair.ps1','Rebuild DS_ALGO Local AI without starting it'),
    @('Start','Start.ps1','Start DS_ALGO Local AI'),
    @('Stop','Stop.ps1','Stop services and retain containers'),
    @('Remove','Remove.ps1','Remove project containers and services'),
    @('Health','Health.ps1','Check local AI service health'),
    @('Uninstall','Uninstall.ps1','Permanently uninstall DS_ALGO Local AI')
  )
  foreach($entry in $entries){
    $script=Join-Path $Root $entry[1]
    New-ScriptShortcut (Join-Path $locations.StartMenu "$($entry[0]).lnk") $script $entry[2]
    if($entry[0] -in @('Install','Repair','Start')){
      New-ScriptShortcut (Join-Path $locations.Desktop "DS_ALGO Local AI - $($entry[0]).lnk") $script $entry[2]
    }
  }
}

function Remove-LocalAIShortcuts {
  $locations=Get-ShortcutLocations
  foreach($name in @('Install','Repair','Start')){
    Remove-Item -LiteralPath (Join-Path $locations.Desktop "DS_ALGO Local AI - $name.lnk") -Force -ErrorAction SilentlyContinue
  }
  if(Test-Path -LiteralPath $locations.StartMenu){
    Remove-Item -LiteralPath $locations.StartMenu -Recurse -Force
  }
}
