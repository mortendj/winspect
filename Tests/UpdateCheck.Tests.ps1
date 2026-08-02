BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/UpdateCheck.ps1"
}

Describe "Get-UpdateNotice" {
    # Mocks Get-LatestReleaseVersion (Winspect's own wrapper), not Invoke-RestMethod directly -
    # this function must never throw regardless of what the real network call does, so the
    # behavior that matters is "what does Get-UpdateNotice do with what its wrapper returns/throws".

    It "returns a notice mentioning both versions when a newer release exists" {
        Mock Get-LatestReleaseVersion { "99.0.0" }

        $notice = Get-UpdateNotice

        $notice | Should -Match "newer version"
        $notice | Should -Match "99.0.0"
        $notice | Should -Match $SCRIPT_VERSION
        $notice | Should -Match $GITHUB_RELEASES_URL
    }

    It "returns an empty string when already on the latest version" {
        Mock Get-LatestReleaseVersion { $SCRIPT_VERSION }
        Get-UpdateNotice | Should -Be ""
    }

    It "returns an empty string when the running version is newer than the latest release" {
        # Plausible in a dev/pre-release build - should never claim an "update" backwards.
        Mock Get-LatestReleaseVersion { "0.0.1" }
        Get-UpdateNotice | Should -Be ""
    }

    It "returns an empty string, without throwing, when the version check fails" {
        Mock Get-LatestReleaseVersion { throw "simulated network failure" }
        { Get-UpdateNotice } | Should -Not -Throw
        Get-UpdateNotice | Should -Be ""
    }
}
