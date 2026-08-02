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
