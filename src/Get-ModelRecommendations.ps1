Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DeterministicModelRecommendations {
    param(
        [ValidateSet('GeneralChat','Reasoning','Coding','DeepResearch','All')][string]$UseCase = 'GeneralChat',
        [string]$CatalogPath = ''
    )
    $ramGiB = 0
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $ramGiB = [math]::Round($os.TotalVisibleMemorySize / 1MB) } catch { }
    if($ramGiB-le0){try{$computer=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop;$ramGiB=[math]::Round([double]$computer.TotalPhysicalMemory/1GB)}catch{}}
    $vramGiB = 0
    $gpuName = 'CPU only'
    try {
        $smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        if ($smi) {
            $line = (& $smi.Source '--query-gpu=name,memory.total' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
            if ($line -match '^\s*(.+?),\s*(\d+)\s*$') { $gpuName=$matches[1].Trim(); $vramGiB=[math]::Round([double]$matches[2]/1024) }
        }
        if ($gpuName -eq 'CPU only') {
            $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Intel' -and $_.Name -notmatch 'Virtual|Remote|Basic Display' } | Sort-Object @{Expression={if($_.Name -match 'NVIDIA'){0}else{1}}} | Select-Object -First 1
            if ($gpu) { $gpuName=[string]$gpu.Name; if ($gpu.AdapterRAM) { $vramGiB=[math]::Round([double]$gpu.AdapterRAM / 1GB) } }
        }
    } catch { }
    $catalogUrl = 'https://dsalgo-model-catalog.vercel.app/dsalgo/v1/get-catalog'
    $catalog = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($CatalogPath) -and (Test-Path -LiteralPath $CatalogPath)) {
            $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
        } else {
            $lastError = $null
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    $response = Invoke-WebRequest -Uri $catalogUrl -Method Get -Headers @{ Accept = 'application/json' } -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
                    $catalog = $response.Content | ConvertFrom-Json
                    break
                } catch { $lastError = $_.Exception.Message; if ($attempt -lt 3) { Start-Sleep -Seconds 2 } }
            }
            if ($null -eq $catalog) { throw "The catalog request failed after 3 attempts. $lastError" }
        }
        if ($catalog.schemaVersion -ne 2 -or @($catalog.models).Count -eq 0) { throw 'The catalog response has an unsupported schema or no models.' }
    } catch { throw "Unable to load the model catalog from $catalogUrl. $($_.Exception.Message)" }
    $tasks=switch($UseCase){'DeepResearch'{@('DocumentQa','Reasoning')}'All'{@('GeneralChat','Reasoning','Coding','DocumentQa')}default{@($UseCase)}}
    $models = @($catalog.models) | Where-Object {
      $candidate=$_; @($tasks|Where-Object{$candidate.tasks -contains $_}).Count -gt 0 -and $candidate.minRamGiB -le $ramGiB -and $candidate.minVramGiB -le $vramGiB
    }
    if (@($models).Count -eq 0) { $models = @($catalog.models) | Where-Object { $_.minRamGiB -le $ramGiB -and $_.minVramGiB -le $vramGiB } }
    $recommendations = @($models | Sort-Object @{Expression='qualityScore';Descending=$true}, @{Expression='minVramGiB';Descending=$true}, id | ForEach-Object {
        [ordered]@{ id=$_.id; displayName=$_.displayName; ollamaTag=$_.ollamaTag; useCase=$UseCase; detectedRamGiB=$ramGiB; detectedVramGiB=$vramGiB; gpu=$gpuName }
    })
    [ordered]@{ status= if($recommendations.Count -gt 0){'success'}else{'no_viable_local_llm'}; hardware=[ordered]@{ramGiB=$ramGiB;vramGiB=$vramGiB;gpu=$gpuName}; recommendations=$recommendations; catalogVersion=$catalog.catalogVersion }
}
