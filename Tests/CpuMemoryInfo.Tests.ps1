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
