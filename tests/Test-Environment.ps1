Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\scripts\Common.ps1"

$cases = @{
  'Central Standard Time' = 'America/Chicago'
  'India Standard Time' = 'Asia/Calcutta'
  'UTC' = 'Etc/UTC'
  'Asia/Kolkata' = 'Asia/Kolkata'
}
foreach($case in $cases.GetEnumerator()){
  $actual=Get-SystemIanaTimeZone $case.Key
  if($actual-ne$case.Value){throw "Expected '$($case.Key)' to map to '$($case.Value)', got '$actual'."}
}

$resolved=Resolve-TimeZonePlaceholder 'TZ=detect-system-timezone-during-install' 'India Standard Time'
if($resolved-ne'TZ=Asia/Calcutta'){throw "Expected the environment placeholder to resolve for India, got '$resolved'."}
$explicit=Resolve-TimeZonePlaceholder 'TZ=Asia/Kolkata' 'Central Standard Time'
if($explicit-ne'TZ=Asia/Kolkata'){throw 'An explicit environment time zone must be preserved.'}

$failed=$false
try{Get-SystemIanaTimeZone 'Unknown Test Time Zone'|Out-Null}catch{$failed=$true}
if(-not$failed){throw 'An unknown Windows time zone must fail with an actionable error.'}

Write-Host 'Environment time-zone tests passed.'
