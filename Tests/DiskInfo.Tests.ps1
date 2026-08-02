BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/SystemQuery.ps1"
    . "$PSScriptRoot/../src/DiskInfo.ps1"
}

Describe "Get-Disks" {
    It "filters logical disks down to fixed drives only (DriveType 3)" {
        Mock Get-MyWmiObject {
            @(
                [pscustomobject]@{ DeviceID = "C:"; DriveType = 3 },
                [pscustomobject]@{ DeviceID = "D:"; DriveType = 5 } # CD-ROM, should be excluded
            )
        } -ParameterFilter { $className -eq "Win32_LogicalDisk" }

        $disks = Get-Disks
        $disks.Count | Should -Be 1
        $disks[0].DeviceID | Should -Be "C:"
    }
}

Describe "Get-DiskCapacity" {
    It "reports used and total space in GB for each fixed disk" {
        Mock Get-MyWmiObject {
            @(
                [pscustomobject]@{ DeviceID = "C:"; DriveType = 3; Size = 500GB; FreeSpace = 200GB }
            )
        } -ParameterFilter { $className -eq "Win32_LogicalDisk" }

        $result = Get-DiskCapacity
        $result | Should -Match "C: -> 300"
        $result | Should -Match "500"
    }

    It "does not insert a thousands-separator when capacity is 1000 GB or more" {
        Mock Get-MyWmiObject {
            @(
                [pscustomobject]@{ DeviceID = "C:"; DriveType = 3; Size = 1500GB; FreeSpace = 500GB }
            )
        } -ParameterFilter { $className -eq "Win32_LogicalDisk" }

        $result = Get-DiskCapacity
        $result | Should -Not -Match ","
        $result | Should -Match "1000\.0 GB / 1500\.0 GB"
    }

    It "uses a period decimal separator regardless of the current culture" {
        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
            Mock Get-MyWmiObject {
                @(
                    [pscustomobject]@{ DeviceID = "C:"; DriveType = 3; Size = 454.9GB; FreeSpace = 102.1GB }
                )
            } -ParameterFilter { $className -eq "Win32_LogicalDisk" }

            Get-DiskCapacity | Should -Not -Match ","
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
    }
}

Describe "Invoke-WinSATCommand" {
    BeforeEach {
        # Invoke-WinSATCommand caches per-drive results in this hashtable at module scope - reset
        # it between tests so caching behavior can be tested deliberately, not by accident.
        $winsatMeasurements = @{}
        $script:fakeWinsatOutput = @(
            "Windows System Assessment Tool",
            "> Disk  Sequential 64.0 Read                       352.12 MB/s          7.0",
            "> Disk  Random 16.0 Read                          1729.46 MB/s          7.9",
            "> Disk  Sequential 64.0 Write                     1637.59 MB/s          7.8",
            "> Disk Responsiveness: Average Read Time 95th Percentile      0.671 ms"
        )
    }

    It "scrapes exactly 3 MB/s speed values from real-shaped winsat output" {
        Mock Invoke-ExternalCommand { $script:fakeWinsatOutput }
        $speeds = Measure-DiskSpeed "C:"
        $speeds | Should -Be @("352.12", "1729.46", "1637.59")
    }

    It "scrapes the 95th percentile latency value from real-shaped winsat output" {
        Mock Invoke-ExternalCommand { $script:fakeWinsatOutput }
        $latency = Measure-DiskLatency "C:"
        $latency | Should -Be @("0.671 ms")
    }

    It "only invokes winsat once per drive letter across multiple calls (caches the result)" {
        Mock Invoke-ExternalCommand { $script:fakeWinsatOutput }
        Measure-DiskSpeed "C:" | Out-Null
        Measure-DiskLatency "C:" | Out-Null
        Should -Invoke -CommandName Invoke-ExternalCommand -Times 1 -Exactly
    }

    It "throws from Measure-DiskSpeed when winsat output doesn't contain exactly 3 speed values" {
        Mock Invoke-ExternalCommand { @("no speed data here") }
        { Measure-DiskSpeed "C:" } | Should -Throw
    }

    It "throws from Measure-DiskLatency when winsat output has no latency value" {
        Mock Invoke-ExternalCommand { @("no latency data here") }
        { Measure-DiskLatency "C:" } | Should -Throw
    }
}
