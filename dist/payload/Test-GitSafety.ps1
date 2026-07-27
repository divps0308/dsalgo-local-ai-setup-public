param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root=$PSScriptRoot

$forbidden=@(
  '^\.env$',
  '^runtime/',
  '^backups/',
  '^config/personal-',
  '^config/(secrets|oauth-tokens)\.dpapi\.json$',
  '^benchmark-results\.json$'
)
if(-not(Test-Path -LiteralPath (Join-Path $Root '.git'))){
  Write-Host 'No Git repository is initialized. Ignore rules are present; tracked-file validation was skipped.'
  exit 0
}
if(-not(Get-Command git -ErrorAction SilentlyContinue)){throw 'Git is required for tracked-file validation.'}
$tracked=@(& git -C $Root ls-files)
$violations=@($tracked|Where-Object{$path=$_;@($forbidden|Where-Object{$path-match$_}).Count-gt 0})
if($violations.Count){
  throw "Unsafe machine-local files are tracked:`n$($violations -join "`n")"
}
Write-Host 'Git safety check passed: no ignored personal, secret, runtime, or backup files are tracked.'
