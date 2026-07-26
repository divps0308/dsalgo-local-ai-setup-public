param([switch]$OpenBrowser)
. "$PSScriptRoot\scripts\Common.ps1"
if(Test-IsAdmin){throw 'Refusing to start Developer Workbench elevated. Open a normal non-Administrator PowerShell window and run Start.ps1 or Start-DeveloperWorkbench.ps1.'}
$port=Get-WorkbenchPort
$python=Get-NativePython
$pythonw=Join-Path (Split-Path -Parent $python) 'pythonw.exe'
if(Test-Path -LiteralPath $pythonw){$python=$pythonw}
$runtime=Join-Path $Root 'runtime\developer-workbench'
$pidFile=Join-Path $runtime 'workbench.pid'
$stdoutFile=Join-Path $runtime 'stdout.log'
$stderrFile=Join-Path $runtime 'stderr.log'
New-Item -ItemType Directory -Force $runtime|Out-Null
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
  $process=Start-Process -FilePath $python -ArgumentList @($app,'--port',"$port") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
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
