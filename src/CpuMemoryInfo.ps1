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

# A single instantaneous reading (above) is noisy - a momentary spike from an unrelated process can
# dominate the number. Start-CpuMemoryMonitoring kicks off a background job, as early as possible
# (called from Invoke-Winspect.ps1 right after parameters are parsed), that samples CPU/memory
# periodically for $periodMinutes so the report can show an average/peak instead. Running it in the
# background means the sampling period mostly overlaps with the rest of the report being built,
# rather than adding to the script's wall-clock time.
$script:CpuMemoryMonitoringJob = $null

function Start-CpuMemoryMonitoring($periodMinutes, $samplingIntervalSeconds) {
    Write-FunctionCallLog $PSBoundParameters
    if ($samplingIntervalSeconds -le 0) {
        return
    }
    $iterations = [math]::Max(1, [math]::Round(($periodMinutes * 60) / $samplingIntervalSeconds))
    $samplingScriptBlock = {
        param($iterations, $intervalSeconds)
        $cpuSamples = @()
        $memorySamples = @()
        for ($i = 0; $i -lt $iterations; $i++) {
            $startTime = Get-Date
            $processor = Get-CimInstance -ClassName Win32_Processor
            $cpuSamples += ($processor | Measure-Object -Property LoadPercentage -Average).Average
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
            $usedMemory = $operatingSystem.TotalVisibleMemorySize - $operatingSystem.FreePhysicalMemory
            $memorySamples += ($usedMemory / $operatingSystem.TotalVisibleMemorySize) * 100
            $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
            $sleepSeconds = $intervalSeconds - $elapsedSeconds
            if (($sleepSeconds -gt 0) -and ($i -lt ($iterations - 1))) {
                Start-Sleep -Seconds $sleepSeconds
            }
        }
        [PSCustomObject]@{ Cpu = $cpuSamples; Memory = $memorySamples }
    }
    $script:CpuMemoryMonitoringJob = Start-Job -ScriptBlock $samplingScriptBlock -ArgumentList $iterations, $samplingIntervalSeconds
}

# Cached so the four Get-Average/PeakXUsage functions below can each ask for the sample set without
# re-receiving (and thus emptying) the background job's output stream more than once.
$script:CpuMemorySamplesCache = $null

function Get-CpuMemorySamples() {
    Write-FunctionCallLog $PSBoundParameters
    if ($null -eq $script:CpuMemorySamplesCache) {
        if ($null -ne $script:CpuMemoryMonitoringJob) {
            $jobResult = Receive-Job -Job $script:CpuMemoryMonitoringJob -Wait
            Remove-Job -Job $script:CpuMemoryMonitoringJob
            $script:CpuMemoryMonitoringJob = $null
            $script:CpuMemorySamplesCache = [PSCustomObject]@{ Cpu = @($jobResult.Cpu); Memory = @($jobResult.Memory) }
        } else {
            # Safety net - monitoring was never started (e.g. sampling disabled). Falls back to one
            # instantaneous reading so the average/peak functions below still return something.
            $processor = Get-MyWmiObject Win32_Processor
            $operatingSystem = Get-MyWmiObject Win32_OperatingSystem
            $cpuSample = ($processor | Measure-Object -Property LoadPercentage -Average).Average
            $usedMemory = $operatingSystem.TotalVisibleMemorySize - $operatingSystem.FreePhysicalMemory
            $memorySample = ($usedMemory / $operatingSystem.TotalVisibleMemorySize) * 100
            $script:CpuMemorySamplesCache = [PSCustomObject]@{ Cpu = @($cpuSample); Memory = @($memorySample) }
        }
    }
    Write-ReturnValue $script:CpuMemorySamplesCache
}

function Get-AverageCpuUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $samples = Get-CpuMemorySamples
    $roundedAverage = [math]::Round(($samples.Cpu | Measure-Object -Average).Average, 1)
    Write-ReturnValue (Format-InvariantNumber $roundedAverage)
}

function Get-PeakCpuUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $samples = Get-CpuMemorySamples
    $roundedPeak = [math]::Round(($samples.Cpu | Measure-Object -Maximum).Maximum, 1)
    Write-ReturnValue (Format-InvariantNumber $roundedPeak)
}

function Get-AverageMemoryUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $samples = Get-CpuMemorySamples
    $roundedAverage = [math]::Round(($samples.Memory | Measure-Object -Average).Average, 1)
    Write-ReturnValue (Format-InvariantNumber $roundedAverage)
}

function Get-PeakMemoryUsage() {
    Write-FunctionCallLog $PSBoundParameters
    $samples = Get-CpuMemorySamples
    $roundedPeak = [math]::Round(($samples.Memory | Measure-Object -Maximum).Maximum, 1)
    Write-ReturnValue (Format-InvariantNumber $roundedPeak)
}
