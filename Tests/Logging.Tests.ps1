BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
}

Describe "Limit-TextString" {
    It "collapses CRLF newlines to [LF] markers" {
        Limit-TextString "line1`r`nline2" | Should -Be "line1[LF]line2"
    }

    It "collapses bare LF newlines to [LF] markers" {
        Limit-TextString "line1`nline2`nline3" | Should -Be "line1[LF]line2[LF]line3"
    }

    It "leaves short strings unchanged" {
        Limit-TextString "short" | Should -Be "short"
    }

    It "truncates strings longer than the max length and appends an ellipsis" {
        $longString = "x" * ($MAX_LOG_LINE_LENGTH + 100)
        $result = Limit-TextString $longString
        $result.Length | Should -Be $MAX_LOG_LINE_LENGTH
        $result.EndsWith("...") | Should -BeTrue
    }
}

Describe "Get-VariableDisplayValue" {
    It "reports NULL for a null value" {
        Get-VariableDisplayValue $null | Should -Be "NULL"
    }

    It "reports a label for an empty string rather than an invisible blank" {
        Get-VariableDisplayValue "" | Should -Be "an empty string"
    }

    It "reports an array's element count" {
        Get-VariableDisplayValue @(1, 2, 3) | Should -Be "System.Object[3]"
    }

    It "reports a hashtable's entry count" {
        Get-VariableDisplayValue @{a = 1; b = 2 } | Should -Be "System.Collections.Hashtable[2]"
    }

    It "renders simple scalar values via ToString" {
        Get-VariableDisplayValue 42 | Should -Be "42"
    }

    It "renders boolean values via ToString" {
        Get-VariableDisplayValue $true | Should -Be "True"
    }
}

Describe "Get-ErrorOutput" {
    It "prefixes a plain message with the error prefix" {
        Get-ErrorOutput "Something failed" | Should -Be "$ERROR_PREFIX Something failed"
    }

    It "does not double-prefix a message that already has the prefix" {
        $alreadyPrefixed = "$ERROR_PREFIX Something failed"
        Get-ErrorOutput $alreadyPrefixed | Should -Be $alreadyPrefixed
    }
}

Describe "Write-ErrorLog" {
    It "does not throw when called without an exception" {
        { Write-ErrorLog "Something failed" } | Should -Not -Throw
    }

    It "does not throw when called with a real exception object" {
        $caughtException = $null
        try { throw "boom" } catch { $caughtException = $_ }
        { Write-ErrorLog "Something failed" $caughtException } | Should -Not -Throw
    }
}
