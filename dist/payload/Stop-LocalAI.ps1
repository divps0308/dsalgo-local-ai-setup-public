param([switch]$StopOllama)
& "$PSScriptRoot\Stop.ps1"
if($StopOllama){Get-Process ollama -ErrorAction SilentlyContinue|Stop-Process -Force}
