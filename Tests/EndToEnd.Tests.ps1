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
        $reportText | Should -Match "HOST IDENTITY"
        $reportText | Should -Match "NETWORK"
        $reportText | Should -Match "SYSTEM RESOURCES"
        $reportText | Should -Match "RESOURCE USAGE"
        $reportText | Should -Match "CERTIFICATES"
        $reportText | Should -Not -Match "ADDITIONAL CERTIFICATE"
        $reportText | Should -Not -Match "GMSA ACCOUNT"
        $reportText | Should -Match "Running elevated: (Yes|No)"
        $reportText | Should -Match "Hostname: \S+"
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

    It "shows the GMSA ACCOUNT section only when -gmsaAccountName is supplied" {
        # This dev/CI machine is assumed not domain-joined, so the specific message asserted here
        # is a real-environment assumption, not a universal guarantee - if this suite ever runs on
        # a domain-joined machine, this assertion (though not the section-presence one above it)
        # would need updating to match. Real account existence/usability can only be confirmed on
        # an actual domain-joined host with a real gMSA name.
        Push-Location $TestDrive
        try {
            $output = (& $winspectScript -outputFormat text -skipDiskPerformanceMeasurements -outputDestination terminal -gmsaAccountName "svc-test") -join "`n"
        } finally {
            Pop-Location
        }

        $output | Should -Match "GMSA ACCOUNT"
        $output | Should -Match "Account name: svc-test"
        $output | Should -Match "not domain-joined"
        $output | Should -Not -Match "ERROR -->"
    }

    It "checks a live TLS endpoint's real certificate when -certificateHostname is supplied" {
        # Depends on real network access and GitHub's own certificate - reasonable given this
        # suite already depends on real system/network state elsewhere (e.g. the update check).
        Push-Location $TestDrive
        try {
            $output = (& $winspectScript -outputFormat text -skipDiskPerformanceMeasurements -outputDestination terminal -certificateHostname "github.com") -join "`n"
        } finally {
            Pop-Location
        }

        $output | Should -Match "ADDITIONAL CERTIFICATE"
        $output | Should -Match "github\.com -> expires \d{4}-\d{2}-\d{2} \(\d+ days\)"
        $output | Should -Not -Match "ERROR -->"
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
