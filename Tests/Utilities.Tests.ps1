BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
}

Describe "Format-InvariantNumber" {
    BeforeEach {
        $script:originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("nb-NO")
    }

    AfterEach {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $script:originalCulture
    }

    It "formats without an explicit format string using a period decimal separator, regardless of current culture" {
        # nb-NO uses a comma decimal separator - this is the exact bug the tool used to have.
        Format-InvariantNumber 17.5 | Should -Be "17.5"
    }

    It "formats with an explicit format string using a period decimal separator, regardless of current culture" {
        Format-InvariantNumber 352.7 "N1" | Should -Be "352.7"
    }

    It "formats whole numbers without unwanted decimals when no format string is given" {
        Format-InvariantNumber 12 | Should -Be "12"
    }

    It "does not insert a thousands-separator for values over 1000 when using an F format string" {
        # Regression test: "N" format specifiers always group thousands (e.g. "2,770.18"), which
        # is wrong here since nothing else in the report groups thousands - "F" format specifiers
        # don't. This bug shipped and was only caught because it happened to show up in real usage
        # (a disk read speed over 1000 MB/s) - no test had exercised a value that large before.
        Format-InvariantNumber 2770.18 "F2" | Should -Be "2770.18"
    }
}

Describe "Invoke-WithRetry" {
    It "runs the command once when it succeeds immediately" {
        $script:callCount = 0
        Invoke-WithRetry -command { $script:callCount++ } -functionName "Test-Command"
        $script:callCount | Should -Be 1
    }

    It "retries until success within maxRetries" {
        $script:callCount = 0
        Invoke-WithRetry -command {
            $script:callCount++
            if ($script:callCount -lt 3) { throw "simulated failure" }
        } -functionName "Test-Command" -maxRetries 5 -retryDelay 0
        $script:callCount | Should -Be 3
    }

    It "throws after exhausting maxRetries" {
        $script:callCount = 0
        {
            Invoke-WithRetry -command { $script:callCount++; throw "always fails" } -functionName "Test-Command" -maxRetries 2 -retryDelay 0
        } | Should -Throw
        $script:callCount | Should -Be 2
    }
}

Describe "Invoke-ExternalCommand" {
    It "passes an argument containing internal whitespace through as a single argument, not split" {
        # Regression test for a real bug found on a production host: Start-Process's -ArgumentList
        # does naive space-joining of the array rather than proper Win32 argv construction, so an
        # argument like a Go template or a SQL query - anything containing internal spaces - arrived
        # at the target process broken into multiple separate arguments instead of the one it was
        # meant to be. Confirmed as "template parsing error: template: :1: unclosed action" from a
        # docker command whose --format argument got split this way. Exercises the real external-
        # process boundary (a real pwsh subprocess), not a mock, since the bug is specifically in
        # how Start-Process constructs the child process's command line.
        $dumpScriptPath = Join-Path $TestDrive "dump-args.ps1"
        Set-Content -Path $dumpScriptPath -Value 'foreach ($a in $args) { Write-Output "ARG:$a" }'

        $result = Invoke-ExternalCommand "pwsh" @("-NoProfile", "-File", $dumpScriptPath, "one two three", "four")

        $result | Should -Contain "ARG:one two three"
        $result | Should -Contain "ARG:four"
    }
}

Describe "Update-FileWriteErrorCount" {
    BeforeEach {
        $script:FileWriteErrorCounts = @{}
    }

    It "starts a new error type at count 1" {
        Update-FileWriteErrorCount "Set-Content"
        $script:FileWriteErrorCounts["Set-Content"] | Should -Be 1
    }

    It "increments an existing error type rather than overwriting it" {
        Update-FileWriteErrorCount "Set-Content"
        Update-FileWriteErrorCount "Set-Content"
        $script:FileWriteErrorCounts["Set-Content"] | Should -Be 2
    }

    It "tracks different error types independently" {
        Update-FileWriteErrorCount "Set-Content"
        Update-FileWriteErrorCount "Add-Content"
        $script:FileWriteErrorCounts["Set-Content"] | Should -Be 1
        $script:FileWriteErrorCounts["Add-Content"] | Should -Be 1
    }
}
