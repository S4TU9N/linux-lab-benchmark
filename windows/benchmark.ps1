# linux lab benchmark
# windows implementation

$ErrorActionPreference = "Continue"

$osName = "Windows 11"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = Get-CimInstance Win32_VideoController |
    Where-Object { $_.Name -notmatch "Microsoft Basic Display Adapter" } |
    Select-Object -First 1

$memoryGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param (
        [string]$Category,
        [string]$Stat,
        $Value,
        [string]$Unit
    )

    $results.Add([PSCustomObject]@{
        os       = $osName
        category = $Category
        stat     = $Stat
        value    = $Value
        unit     = $Unit
    })
}

Write-Host ""
Write-Host "Linux Lab Benchmark - Windows"
Write-Host "============================="
Write-Host "Timestamp: $timestamp"
Write-Host ""

# system information

Add-Result "system" "os" $os.Caption "text"
Add-Result "system" "os_version" $os.Version "text"
Add-Result "system" "cpu_model" $cpu.Name "text"
Add-Result "system" "cpu_cores" $cpu.NumberOfCores "count"
Add-Result "system" "cpu_threads" $cpu.NumberOfLogicalProcessors "count"
Add-Result "system" "ram_total" $memoryGB "GB"

if ($gpu) {
    Add-Result "system" "gpu_model" $gpu.Name "text"
}

# storage information

$physicalDisks = Get-PhysicalDisk

foreach ($disk in $physicalDisks) {
    Add-Result "storage" "disk_model" $disk.FriendlyName "text"
    Add-Result "storage" "disk_size" ([math]::Round($disk.Size / 1GB, 2)) "GB"
    Add-Result "storage" "disk_health" $disk.HealthStatus "text"
}

# idle resource usage

Write-Host "Letting the system settle for 30 seconds..."
Start-Sleep -Seconds 30

$cpuSamples = @()
$ramSamples = @()

Write-Host "Collecting idle resource usage..."

for ($i = 0; $i -lt 10; $i++) {
    $counter = Get-Counter "\Processor(_Total)\% Processor Time"
    $cpuSamples += $counter.CounterSamples[0].CookedValue

    $memory = Get-CimInstance Win32_OperatingSystem
    $usedMemory = $memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory
    $usedMemoryGB = ($usedMemory * 1KB) / 1GB

    $ramSamples += $usedMemoryGB

    Start-Sleep -Seconds 1
}

$idleCpu = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 2)
$idleRam = [math]::Round(($ramSamples | Measure-Object -Average).Average, 2)
$idleRamPercent = [math]::Round(($idleRam / $memoryGB) * 100, 2)

Add-Result "idle" "idle_cpu" $idleCpu "percent"
Add-Result "idle" "idle_ram" $idleRam "GB"
Add-Result "idle" "idle_ram_percent" $idleRamPercent "percent"

# process count

$processCount = (Get-Process).Count
Add-Result "idle" "process_count" $processCount "count"

# export

$resultsDir = Join-Path $PSScriptRoot "..\results"

if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$outputPath = Join-Path $resultsDir "windows-11.csv"

$results | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host ""
Write-Host "Benchmark complete."
Write-Host "Results: $outputPath"
Write-Host ""
Write-Host "Collected results:"
$results | Format-Table -AutoSize
