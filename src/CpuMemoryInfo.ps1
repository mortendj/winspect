function Get-CpuCapacity() {
    Write-FunctionCallLog $PSBoundParameters
    $processors = Get-MyWmiObject Win32_Processor
    $totalLogicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    Write-ReturnValue $totalLogicalProcessors
}

function Get-RamCapacity() {
    Write-FunctionCallLog $PSBoundParameters
    $operatingSystem = Get-MyWmiObject Win32_OperatingSystem
    $totalVisibleMemorySize = $operatingSystem.TotalVisibleMemorySize
    $ramInGB = [math]::Round($totalVisibleMemorySize / (1024 * 1024), 2)
    Write-ReturnValue (Format-InvariantNumber $ramInGB "N0")
}

function Get-CurrentCpuUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $processor = Get-MyWmiObject Win32_Processor
    $cpuLoad = $processor | Measure-Object -Property LoadPercentage -Average
    Write-ReturnValue (Format-InvariantNumber $cpuLoad.Average)
}

function Get-CurrentMemoryUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $operatingSystem = Get-MyWmiObject Win32_OperatingSystem
    $totalMemory = $operatingSystem.TotalVisibleMemorySize
    $freeMemory = $operatingSystem.FreePhysicalMemory
    $usedMemory = $totalMemory - $freeMemory
    $memoryUsagePercentage = [math]::Round(($usedMemory / $totalMemory) * 100, 1)
    Write-ReturnValue (Format-InvariantNumber $memoryUsagePercentage)
}
