BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/SystemQuery.ps1"
    . "$PSScriptRoot/../src/CpuMemoryInfo.ps1"
}

Describe "Get-CpuCapacity" {
    It "sums logical processor counts across all reported processor entries" {
        Mock Get-MyWmiObject {
            @(
                [pscustomobject]@{ NumberOfLogicalProcessors = 8 },
                [pscustomobject]@{ NumberOfLogicalProcessors = 4 }
            )
        } -ParameterFilter { $className -eq "Win32_Processor" }

        Get-CpuCapacity | Should -Be 12
    }
}

Describe "Get-RamCapacity" {
    It "converts TotalVisibleMemorySize from KB to a whole-number GB string" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ TotalVisibleMemorySize = 16777216 } # 16 GB in KB
        } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

        Get-RamCapacity | Should -Be "16"
    }

    It "does not insert a thousands-separator when capacity is 1000 GB or more" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ TotalVisibleMemorySize = 1073741824 } # 1024 GB in KB
        } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

        Get-RamCapacity | Should -Be "1024"
    }

    It "uses a period decimal separator regardless of the current culture" {
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            Mock Get-MyWmiObject {
                [pscustomobject]@{ TotalVisibleMemorySize = 12000000 } # not a clean whole GB value
            } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

            Get-RamCapacity | Should -Not -Match ","
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }
}

Describe "Get-CurrentCpuUsage" {
    It "averages LoadPercentage across all reported processor entries" {
        Mock Get-MyWmiObject {
            @(
                [pscustomobject]@{ LoadPercentage = 10 },
                [pscustomobject]@{ LoadPercentage = 20 }
            )
        } -ParameterFilter { $className -eq "Win32_Processor" }

        Get-CurrentCpuUsage | Should -Be "15"
    }

    It "rounds to 1 decimal rather than showing a long repeating decimal" {
        # Regression test for a real bug found on a production host: an odd number of processors
        # averaging to a repeating decimal (110 / 6 = 18.333333333333332) was passed straight
        # through with no rounding at all, unlike Get-CurrentMemoryUsage right below, which already
        # rounds - confirmed as "Current CPU load: 18.3333333333333 %" in a real report.
        Mock Get-MyWmiObject {
            @(
                [pscustomobject]@{ LoadPercentage = 10 },
                [pscustomobject]@{ LoadPercentage = 10 },
                [pscustomobject]@{ LoadPercentage = 11 }
            )
        } -ParameterFilter { $className -eq "Win32_Processor" }

        # (10 + 10 + 11) / 3 = 10.3333... -> rounded to 1 decimal
        Get-CurrentCpuUsage | Should -Be "10.3"
    }

    It "uses a period decimal separator regardless of the current culture" {
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            Mock Get-MyWmiObject {
                @(
                    [pscustomobject]@{ LoadPercentage = 10 },
                    [pscustomobject]@{ LoadPercentage = 10 },
                    [pscustomobject]@{ LoadPercentage = 11 }
                )
            } -ParameterFilter { $className -eq "Win32_Processor" }

            Get-CurrentCpuUsage | Should -Be "10.3"
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }
}

Describe "Get-CpuMemorySamples" {
    BeforeEach {
        $script:CpuMemoryMonitoringJob = $null
        $script:CpuMemorySamplesCache = $null
    }

    It "receives and caches the background monitoring job's samples, only once" {
        $fakeJob = Start-Job -ScriptBlock { [PSCustomObject]@{ Cpu = @(10, 20, 30); Memory = @(40, 50, 60) } }
        $script:CpuMemoryMonitoringJob = $fakeJob
        Wait-Job $fakeJob | Out-Null

        $first = Get-CpuMemorySamples
        $second = Get-CpuMemorySamples

        $first.Cpu | Should -Be @(10, 20, 30)
        $first.Memory | Should -Be @(40, 50, 60)
        $second.Cpu | Should -Be @(10, 20, 30)
        $script:CpuMemoryMonitoringJob | Should -BeNullOrEmpty
    }

    It "falls back to a single instantaneous reading when monitoring was never started" {
        Mock Get-MyWmiObject {
            @([pscustomobject]@{ LoadPercentage = 25 })
        } -ParameterFilter { $className -eq "Win32_Processor" }
        Mock Get-MyWmiObject {
            [pscustomobject]@{ TotalVisibleMemorySize = 3000; FreePhysicalMemory = 1000 }
        } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

        $samples = Get-CpuMemorySamples

        $samples.Cpu | Should -Be @(25)
        $samples.Memory[0] | Should -BeGreaterThan 66.6
        $samples.Memory[0] | Should -BeLessThan 66.7
    }
}

Describe "Get-AverageCpuUsage / Get-PeakCpuUsage / Get-AverageMemoryUsage / Get-PeakMemoryUsage" {
    BeforeEach {
        $script:CpuMemoryMonitoringJob = $null
        $script:CpuMemorySamplesCache = [PSCustomObject]@{ Cpu = @(10, 20, 30); Memory = @(40, 55, 70) }
    }

    It "averages the cached CPU samples" {
        Get-AverageCpuUsage | Should -Be "20"
    }

    It "reports the peak of the cached CPU samples" {
        Get-PeakCpuUsage | Should -Be "30"
    }

    It "averages the cached memory samples" {
        Get-AverageMemoryUsage | Should -Be "55"
    }

    It "reports the peak of the cached memory samples" {
        Get-PeakMemoryUsage | Should -Be "70"
    }

    It "uses a period decimal separator regardless of the current culture" {
        $script:CpuMemorySamplesCache = [PSCustomObject]@{ Cpu = @(10, 10, 11); Memory = @(10, 10, 11) }
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            Get-AverageCpuUsage | Should -Be "10.3"
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }
}

Describe "Start-CpuMemoryMonitoring" {
    AfterEach {
        if ($null -ne $script:CpuMemoryMonitoringJob) {
            Remove-Job -Job $script:CpuMemoryMonitoringJob -Force -ErrorAction SilentlyContinue
            $script:CpuMemoryMonitoringJob = $null
        }
    }

    It "does not start a background job when sampling is disabled" {
        Start-CpuMemoryMonitoring 2 0
        $script:CpuMemoryMonitoringJob | Should -BeNullOrEmpty
    }

    It "starts a background job that returns real CPU/memory samples when sampling is enabled" {
        Start-CpuMemoryMonitoring 0.05 2
        $script:CpuMemoryMonitoringJob | Should -Not -BeNullOrEmpty
        $result = Receive-Job -Job $script:CpuMemoryMonitoringJob -Wait
        $result.Cpu.Count | Should -BeGreaterThan 0
        $result.Memory.Count | Should -BeGreaterThan 0
    }
}

Describe "Get-CurrentMemoryUsage" {
    It "computes used-memory percentage from total and free memory" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ TotalVisibleMemorySize = 3000; FreePhysicalMemory = 1000 }
        } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

        # (3000 - 1000) / 3000 * 100 = 66.666... -> rounded to 1 decimal
        Get-CurrentMemoryUsage | Should -Be "66.7"
    }

    It "uses a period decimal separator regardless of the current culture" {
        # This is the exact bug class the tool used to have: a fractional percentage rendered
        # with a comma on a Norwegian-formatted OS, while other fields used periods.
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            Mock Get-MyWmiObject {
                [pscustomobject]@{ TotalVisibleMemorySize = 3000; FreePhysicalMemory = 1000 }
            } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

            Get-CurrentMemoryUsage | Should -Be "66.7"
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }
}
