# Runs the real entry point with no mocks at all - the layer that catches integration bugs
# unit tests can't see, at the cost of depending on real system state. Assertions check output
# *shape* (patterns, section presence) rather than exact values, since CPU load/RAM usage/etc.
# vary from run to run and machine to machine.

BeforeAll {
    $winspectScript = Resolve-Path "$PSScriptRoot/../Invoke-Winspect.ps1"
}

Describe "Invoke-Winspect end-to-end" {
    It "produces a version string and exits when -version is passed" {
        $output = & $winspectScript -version
        $output | Should -Match "^Winspect v\. \d+\.\d+\.\d+"
    }

    It "produces a complete, error-free text report to the terminal" {
        Push-Location $TestDrive
        try {
            $output = & $winspectScript -outputFormat text -skipDiskPerformanceMeasurements -outputDestination terminal
        } finally {
            Pop-Location
        }
        $reportText = $output -join "`n"

        $reportText | Should -Match "REPORT INFO"
        $reportText | Should -Match "SYSTEM RESOURCES"
        $reportText | Should -Match "CPU cores: \d+"
        $reportText | Should -Match "RAM capacity: \d+ GB"
        $reportText | Should -Match "Current CPU load: [\d.]+ %"
        $reportText | Should -Match "Current RAM usage: [\d.]+ %"
        $reportText | Should -Not -Match "ERROR -->"
    }

    It "produces valid-looking markdown and html reports without errors" {
        Push-Location $TestDrive
        try {
            $markdown = (& $winspectScript -outputFormat markdown -skipDiskPerformanceMeasurements -outputDestination terminal) -join "`n"
            $html = (& $winspectScript -outputFormat html -skipDiskPerformanceMeasurements -outputDestination terminal) -join "`n"
        } finally {
            Pop-Location
        }

        $markdown | Should -Match "\*\*CPU cores:\*\*"
        $markdown | Should -Not -Match "ERROR -->"

        $html | Should -Match "<html><body>"
        $html | Should -Match "<b>CPU cores:</b>"
        $html | Should -Not -Match "ERROR -->"
    }

    It "writes a report file into the current directory when the destination includes file" {
        Push-Location $TestDrive
        try {
            & $winspectScript -outputFormat text -skipDiskPerformanceMeasurements -outputDestination file | Out-Null
            Test-Path (Join-Path $TestDrive "winspect-report.txt") | Should -BeTrue
        } finally {
            Pop-Location
        }
    }

    It "never uses a comma as a decimal separator anywhere in the report" {
        # Regression test for the locale bug: the report used to mix comma- and period-decimals
        # depending on which code path produced each number.
        Push-Location $TestDrive
        try {
            $output = (& $winspectScript -outputFormat text -skipDiskPerformanceMeasurements -outputDestination terminal) -join "`n"
        } finally {
            Pop-Location
        }
        $output | Should -Not -Match "\d,\d"
    }
}
