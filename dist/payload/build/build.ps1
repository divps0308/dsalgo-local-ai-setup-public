Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $repoRoot 'dist'
$artifacts = Join-Path $repoRoot 'artifacts'
$appName = 'DSAlgo Local AI Setup'
$version = '1.0.0'
$sourceScript = Join-Path $repoRoot 'src\InstallerWizard.ps1'
$outputExe = Join-Path $dist 'install.exe'
$certificateSubject = 'CN=DSAlgo Local AI Setup Local Release Signing'

New-Item -ItemType Directory -Force -Path $dist, $artifacts | Out-Null
if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Installer source was not found: $sourceScript"
}

# Windows may redirect Documents to OneDrive without adding the redirected
# WindowsPowerShell module directory to PSModulePath in every host process.
$userShellFolders = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
$personalFolders = @()
if ($userShellFolders) { $personalFolders += [Environment]::ExpandEnvironmentVariables([string]$userShellFolders.Personal) }
foreach ($oneDriveRoot in @($env:OneDrive, $env:OneDriveConsumer)) {
    if (-not [string]::IsNullOrWhiteSpace($oneDriveRoot)) { $personalFolders += Join-Path $oneDriveRoot 'Documents' }
}
foreach ($personalFolder in @($personalFolders | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
    $redirectedModules = Join-Path $personalFolder 'WindowsPowerShell\Modules'
    if ((Test-Path -LiteralPath $redirectedModules) -and $redirectedModules -notin @($env:PSModulePath -split ';')) {
        $env:PSModulePath = "$redirectedModules;$env:PSModulePath"
    }
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -ErrorAction Stop
if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    throw 'PS2EXE was imported but Invoke-ps2exe is unavailable. Existing release artifacts were not changed.'
}

# Always regenerate the browser bundles before packaging. Copying previously
# generated static assets can otherwise ship an older UI even when the Svelte
# source has changed.
$frontendManifest = Join-Path $repoRoot 'frontend\package.json'
if (-not (Test-Path -LiteralPath $frontendManifest)) { throw "Frontend manifest was not found: $frontendManifest" }
$pnpm = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
if (-not $pnpm) { $pnpm = Get-Command pnpm -ErrorAction SilentlyContinue }
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) { $node = Get-Command node -ErrorAction SilentlyContinue }
if (-not $node) { throw 'Node.js is required for the release build. Install Node.js (or select it with nvm) and reopen PowerShell.' }
if (-not $pnpm) { throw 'pnpm is required for the release build. Install it with: npm install --global pnpm' }
Push-Location $repoRoot
try {
    Write-Host 'Building frontend bundles: pnpm --dir frontend build'
    & $pnpm.Source --dir frontend build
    if ($LASTEXITCODE -ne 0) { throw "Frontend build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

# Do not remove the last usable release until all required build tooling has
# loaded successfully.
$generatedNames = @('install','start','stop','repair','remove','uninstall')
foreach ($name in $generatedNames) { Remove-Item -LiteralPath (Join-Path $dist "$name.exe") -Force -ErrorAction SilentlyContinue }
foreach ($file in @('SHA256SUMS.txt','VERIFY.md')) { Remove-Item -LiteralPath (Join-Path $dist $file) -Force -ErrorAction SilentlyContinue }

$payloadRoot = Join-Path $dist 'payload'
if (Test-Path -LiteralPath $payloadRoot) { Remove-Item -LiteralPath $payloadRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null
Get-ChildItem -LiteralPath $repoRoot -Force |
    Where-Object { $_.Name -notin @('.git','dist','artifacts','.env','runtime','backups','node_modules','.pnpm-store') } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $payloadRoot -Recurse -Force }
# The frontend build output is distributable; its dependency tree is not.
Remove-Item -LiteralPath (Join-Path $payloadRoot 'frontend\node_modules') -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath (Join-Path $payloadRoot 'config') -Filter 'personal-*' -File -ErrorAction SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath (Join-Path $payloadRoot 'config\secrets.dpapi.json') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $payloadRoot 'config\oauth-tokens.dpapi.json') -Force -ErrorAction SilentlyContinue

function Wait-FileReady([string]$Path,[int]$Attempts=20) {
    for($i=0;$i -lt $Attempts;$i++) {
        try {
            $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
            $stream.Dispose(); return
        } catch { Start-Sleep -Milliseconds 500 }
    }
    throw "Timed out waiting for the file to become available: $Path. Close any running copy of this EXE and retry."
}

function Sign-ReleaseExe([string]$Path,[object]$Certificate) {
    Wait-FileReady $Path
    for($i=0;$i -lt 5;$i++) {
        try {
            $result=Set-AuthenticodeSignature -FilePath $Path -Certificate $Certificate -HashAlgorithm SHA256
            if($result.SignerCertificate -and $result.SignerCertificate.Thumbprint -eq $Certificate.Thumbprint){ return $result }
        } catch {
            if($i -eq 4){ throw }
        }
        Start-Sleep -Milliseconds 750
    }
    throw "Unable to sign $Path."
}

$icon = Join-Path $repoRoot 'assets\branding\logo.ico'
$params = @{
    inputFile = $sourceScript
    outputFile = $outputExe
    noConsole = $true
    title = $appName
    product = $appName
    company = 'Divya Pratap Srivastava'
    version = $version
    copyright = 'Copyright (c) 2026 Divya Pratap Srivastava'
}
if (Test-Path -LiteralPath $icon) { $params.iconFile = $icon }

# PS2EXE packages a PowerShell-hosted application; it is not native AOT compilation.
Invoke-ps2exe @params

foreach ($entry in @(
    @{ Name='start'; Source='Start.ps1' },
    @{ Name='stop'; Source='Stop.ps1' },
    @{ Name='repair'; Source='Repair.ps1' },
    @{ Name='remove'; Source='Remove.ps1' },
    @{ Name='uninstall'; Source='Uninstall.ps1' }
)) {
    $source = Join-Path $repoRoot $entry.Source
    if (-not (Test-Path -LiteralPath $source)) { throw "Lifecycle source was not found: $source" }
    Invoke-ps2exe -inputFile $source -outputFile (Join-Path $dist "$($entry.Name).exe") -noConsole `
        -title "DSAlgo Local AI Setup - $($entry.Name)" -product $appName -company 'Divya Pratap Srivastava' `
        -version $version -copyright 'Copyright (c) 2026 Divya Pratap Srivastava'
}

$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
    Where-Object { $_.Subject -eq $certificateSubject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $certificateSubject `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 3072 `
        -KeySpec Signature -KeyUsage DigitalSignature -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(3)
}

$cer = Join-Path $dist 'DSAlgo-Local-Release-Signing.cer'
Export-Certificate -Cert $cert -FilePath $cer -Type CERT | Out-Null
$signature = Sign-ReleaseExe $outputExe $cert
if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $cert.Thumbprint) {
    throw "Code signing failed: $($signature.Status) $($signature.StatusMessage)"
}

$verified = Get-AuthenticodeSignature -FilePath $outputExe
if (-not $verified.SignerCertificate -or $verified.SignerCertificate.Thumbprint -ne $cert.Thumbprint) {
    throw "Signature verification failed: $($verified.Status)"
}
$allExes = Get-ChildItem -LiteralPath $dist -Filter '*.exe'
foreach($exe in $allExes){
    $s=Sign-ReleaseExe $exe.FullName $cert
    if(-not $s.SignerCertificate -or $s.SignerCertificate.Thumbprint -ne $cert.Thumbprint){throw "Code signing failed for $($exe.Name): $($s.Status)"}
}
$hash = Get-FileHash -LiteralPath $outputExe -Algorithm SHA256
$sumLines = @($allExes | Sort-Object Name | ForEach-Object { $h=Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256; "$($h.Hash)  $($_.Name)" })
$cerHash = (Get-FileHash -LiteralPath $cer -Algorithm SHA256).Hash
$sumLines += "$cerHash  $([IO.Path]::GetFileName($cer))"
Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Value $sumLines -Encoding UTF8
@"
# Release verification

Get-FileHash .\install.exe -Algorithm SHA256
Get-AuthenticodeSignature .\install.exe | Format-List *

This executable is signed with a self-signed certificate. Verify the certificate
thumbprint from the official GitHub repository before trusting it. Do not import
a downloaded certificate merely because it was downloaded. Installing the .cer
into Trusted Publishers or Trusted Root Certification Authorities is optional,
security-sensitive, and not recommended for ordinary public users.

Self-signing does not eliminate Unknown Publisher or SmartScreen warnings.
"@ | Set-Content -LiteralPath (Join-Path $dist 'VERIFY.md') -Encoding UTF8
Write-Host "Built and signed the DSAlgo Local AI Setup release in $dist."
Write-Host 'Executables: install.exe, start.exe, stop.exe, repair.exe, remove.exe, uninstall.exe.'
Write-Host "Signer: $($verified.SignerCertificate.Subject) / $($verified.SignerCertificate.Thumbprint)"
