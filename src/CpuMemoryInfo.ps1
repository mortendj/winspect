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
    Write-ReturnValue (Format-InvariantNumber $ramInGB "F0")
}

function Get-CurrentCpuUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $processor = Get-MyWmiObject Win32_Processor
    $cpuLoad = $processor | Measure-Object -Property LoadPercentage -Average
    # Rounded to 1 decimal, same as Get-CurrentMemoryUsage - averaging LoadPercentage across an
    # odd number of processors otherwise produces a long repeating decimal (e.g. "18.3333333333333"
    # for 6 processors averaging 110), confirmed on a real customer host.
    $roundedCpuLoad = [math]::Round($cpuLoad.Average, 1)
    Write-ReturnValue (Format-InvariantNumber $roundedCpuLoad)
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
