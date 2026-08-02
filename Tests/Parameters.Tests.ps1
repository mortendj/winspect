BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Parameters.ps1"
}

# Get-AdjustedParameters, Get-AllParameterValues, and Get-CmdLineParameterValues all depend on
# $PSCmdlet/$PSBoundParameters from Invoke-Winspect.ps1's own [CmdletBinding()] - they aren't
# unit-testable in isolation without recreating that binding context. They're exercised instead
# by the end-to-end smoke test, which runs the real entry point.

Describe "Get-ParametersFromFile" {
    It "parses a simple key/value line" {
        $path = Join-Path $TestDrive "params1.txt"
        Set-Content -Path $path -Value "outputFormat markdown"
        $result = Get-ParametersFromFile $path
        $result["outputFormat"] | Should -Be "markdown"
    }

    It "ignores blank lines and comment-only lines" {
        $path = Join-Path $TestDrive "params2.txt"
        Set-Content -Path $path -Value @(
            "# a full-line comment",
            "",
            "   ",
            "outputFormat html"
        )
        $result = Get-ParametersFromFile $path
        $result.Count | Should -Be 1
        $result["outputFormat"] | Should -Be "html"
    }

    It "strips a trailing inline comment from a value" {
        $path = Join-Path $TestDrive "params3.txt"
        Set-Content -Path $path -Value "outputFormat markdown # use markdown for now"
        $result = Get-ParametersFromFile $path
        $result["outputFormat"] | Should -Be "markdown"
    }

    It "converts a bare boolean value to a real [bool]" {
        $path = Join-Path $TestDrive "params4.txt"
        Set-Content -Path $path -Value "skipDiskPerformanceMeasurements true"
        $result = Get-ParametersFromFile $path
        $result["skipDiskPerformanceMeasurements"] | Should -BeOfType [bool]
        $result["skipDiskPerformanceMeasurements"] | Should -BeTrue
    }

    It "converts a dollar-prefixed boolean value to a real [bool]" {
        $path = Join-Path $TestDrive "params5.txt"
        Set-Content -Path $path -Value 'skipDiskPerformanceMeasurements $false'
        $result = Get-ParametersFromFile $path
        $result["skipDiskPerformanceMeasurements"] | Should -BeOfType [bool]
        $result["skipDiskPerformanceMeasurements"] | Should -BeFalse
    }

    It "strips surrounding double quotes from a quoted value" {
        $path = Join-Path $TestDrive "params6.txt"
        Set-Content -Path $path -Value 'parametersFile "C:\some path with spaces.txt"'
        $result = Get-ParametersFromFile $path
        $result["parametersFile"] | Should -Be "C:\some path with spaces.txt"
    }

    It "skips a line with no value rather than throwing" {
        $path = Join-Path $TestDrive "params7.txt"
        Set-Content -Path $path -Value @("justonewordnovalue", "outputFormat text")
        $result = Get-ParametersFromFile $path -WarningAction SilentlyContinue
        $result.ContainsKey("justonewordnovalue") | Should -BeFalse
        $result["outputFormat"] | Should -Be "text"
    }
}
