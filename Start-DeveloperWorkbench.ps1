param([switch]$OpenBrowser)
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
  try { $scriptRoot = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { }
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { throw 'Cannot determine the installed DSAlgo Local AI Setup directory.' }
$commonPath = Join-Path $scriptRoot 'scripts\Common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { throw "Required lifecycle script was not found: $commonPath" }
Invoke-Expression (Get-Content -LiteralPath $commonPath -Raw)
$Root = $scriptRoot
if(Test-IsAdmin){throw 'Refusing to start Developer Workbench elevated. Open a normal non-Administrator PowerShell window and run Start.ps1 or Start-DeveloperWorkbench.ps1.'}
$port=Get-WorkbenchPort
$python=Get-NativePython
$pythonw=Join-Path (Split-Path -Parent $python) 'pythonw.exe'
if(Test-Path -LiteralPath $pythonw){$python=$pythonw}
$runtime=Join-Path $Root 'runtime\developer-workbench'
$pidFile=Join-Path $runtime 'workbench.pid'
$stdoutFile=Join-Path $runtime 'stdout.log'
$stderrFile=Join-Path $runtime 'stderr.log'
# A prior elevated install/repair may have left runtime files owned by
# Administrator. Ensure the signed-in user can persist Workbench state before
# launching Python; this is limited to the application's runtime directory.
try {
  $runtimeParent = Split-Path -Parent $runtime
  New-Item -ItemType Directory -Force -Path $runtimeParent | Out-Null
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $parentAcl = Get-Acl -LiteralPath $runtimeParent
  $parentRule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'Modify','ContainerInherit,ObjectInherit','None','Allow')
  $parentAcl.SetAccessRule($parentRule)
  Set-Acl -LiteralPath $runtimeParent -AclObject $parentAcl
  New-Item -ItemType Directory -Force -Path $runtime | Out-Null
  $acl = Get-Acl -LiteralPath $runtime
  $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'Modify','ContainerInherit,ObjectInherit','None','Allow')
  $acl.SetAccessRule($rule)
  Set-Acl -LiteralPath $runtime -AclObject $acl
} catch { throw "Could not prepare the Developer Workbench runtime directory '$runtime': $($_.Exception.Message)" }
if(Test-Workbench){
  Write-Host "Developer Workbench is already running at http://localhost:$port"
} else {
  if(Test-Path $pidFile){Remove-Item -LiteralPath $pidFile -Force}
  $app=Join-Path $Root 'developer-workbench\app.py'
  $pathKeys=@([Environment]::GetEnvironmentVariables().Keys|Where-Object{$_-ceq'Path'-or$_-ceq'PATH'})
  if($pathKeys.Count-gt 1){
    $pathValue=[Environment]::GetEnvironmentVariable('Path','Process')
    [Environment]::SetEnvironmentVariable('PATH',$null,'Process')
    [Environment]::SetEnvironmentVariable('Path',$pathValue,'Process')
  }
  $process=Start-Process -FilePath $python -ArgumentList @("`"$app`"",'--port',"$port") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
  @{
    pid=$process.Id
    executable=$python
    app=$app
    startedAt=$process.StartTime.ToUniversalTime().ToString('o')
  }|ConvertTo-Json|Set-Content -LiteralPath $pidFile -Encoding UTF8
  $end=(Get-Date).AddSeconds(30)
  do{
    Start-Sleep 1
    if(Test-Workbench){Write-Host "Developer Workbench started at http://localhost:$port";break}
    if($process.HasExited){
      Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
      $detail=''
      if(Test-Path -LiteralPath $stderrFile){
        $lastError=(Get-Content -LiteralPath $stderrFile -Tail 8 -ErrorAction SilentlyContinue)-join' '
        if($lastError){$detail=" Last error: $lastError"}
      }
      throw "Developer Workbench exited with code $($process.ExitCode). See $stderrFile and logs\developer-workbench.log.$detail"
    }
  }while((Get-Date)-lt$end)
  if(-not(Test-Workbench)){throw 'Developer Workbench did not become ready within 30 seconds.'}
}
if($OpenBrowser){Start-Process "http://localhost:$port"}
