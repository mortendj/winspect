BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/ReportFormatting.ps1"
}

Describe "Initialize-OutputFormatLayout" {
    It "sets HTML-specific layout variables for the html format" {
        Initialize-OutputFormatLayout $HTML_STYLE
        $LOGICAL_NEWLINE | Should -Be "$BR$PHYSICAL_NEWLINE"
        $INDENTATION | Should -Be "&nbsp;&nbsp;&nbsp;&nbsp;"
        $START_HEADING | Should -Be "<h2>"
        $END_HEADING | Should -Be "</h2>"
    }

    It "sets Markdown-specific layout variables for the markdown format" {
        Initialize-OutputFormatLayout $MARKDOWN_STYLE
        $LOGICAL_NEWLINE | Should -Be $PHYSICAL_NEWLINE
        $INDENTATION | Should -Be "&nbsp;&nbsp;&nbsp;&nbsp;"
        $START_HEADING | Should -Be "##"
        $END_HEADING | Should -Be ""
    }

    It "sets plain-text layout variables for the text format" {
        Initialize-OutputFormatLayout $TEXT_STYLE
        $LOGICAL_NEWLINE | Should -Be $PHYSICAL_NEWLINE
        $INDENTATION | Should -Be "    "
        $START_HEADING | Should -Be ""
        $END_HEADING | Should -Be ""
    }
}

Describe "Get-CapitalizedTitle" {
    It "title-cases an all-caps section heading" {
        Get-CapitalizedTitle "SYSTEM RESOURCES" | Should -Be "System Resources"
    }

    It "lowercases the word 'And' even though TitleCase would capitalize it" {
        Get-CapitalizedTitle "CPU AND RAM" | Should -Be "Cpu and Ram"
    }

    It "lowercases the word 'In' even though TitleCase would capitalize it" {
        Get-CapitalizedTitle "RESOURCES IN USE" | Should -Be "Resources in Use"
    }
}

Describe "Test-SectionItemHeading" {
    It "returns true for a line containing the section item marker" {
        Test-SectionItemHeading "$SECTION_ITEM_MARKER Disk C: $SECTION_ITEM_MARKER" | Should -BeTrue
    }

    It "returns false for a line without the marker" {
        Test-SectionItemHeading "CPU cores: 12" | Should -BeFalse
    }
}

Describe "Test-DataFieldLine" {
    It "returns false for an empty line" {
        Test-DataFieldLine "" | Should -BeFalse
    }

    It "returns false for a line starting with a non-field character" {
        Test-DataFieldLine "# a comment" | Should -BeFalse
        Test-DataFieldLine "---" | Should -BeFalse
        Test-DataFieldLine "<html>" | Should -BeFalse
    }

    It "returns false for a line with no field label separator" {
        Test-DataFieldLine "just some text" | Should -BeFalse
    }

    It "returns true for a genuine label/value line" {
        Test-DataFieldLine "CPU cores${FIELD_LABEL_SEPARATOR}12" | Should -BeTrue
    }
}

Describe "Get-SectionHeader" {
    It "pads a text-mode section header with hashes on both sides, totalling 60 characters" {
        Initialize-OutputFormatLayout $TEXT_STYLE
        $cmdline_param_OUTPUT_FORMAT = $TEXT_STYLE
        $header = Get-SectionHeader "TEST"
        $header | Should -Match "^#+ TEST #+$"
        $header.Length | Should -BeGreaterOrEqual 60
    }

    It "wraps the title in the configured heading markers for markdown" {
        Initialize-OutputFormatLayout $MARKDOWN_STYLE
        $cmdline_param_OUTPUT_FORMAT = $MARKDOWN_STYLE
        $header = Get-SectionHeader "test section"
        $header | Should -Match "^## Test Section"
    }

    It "exits with an error rather than silently truncating an overly long title" {
        Initialize-OutputFormatLayout $TEXT_STYLE
        $cmdline_param_OUTPUT_FORMAT = $TEXT_STYLE
        Mock Exit-WithErrorMessage { throw "Exit-WithErrorMessage called: $message" }
        { Get-SectionHeader ("x" * 60) } | Should -Throw "*Exit-WithErrorMessage called*"
    }
}

Describe "Complete-Report bold-formatting" {
    BeforeEach {
        $cmdline_param_OUTPUT_DESTINATION = $TERMINAL_OUTPUT
        # Bare assignment (not $script:) so dot-sourced functions from the file-level BeforeAll
        # actually see the override - keeps these tests from writing into the real repo directory.
        $OUTPUT_FILE_NAME = Join-Path $TestDrive "test-report"
    }

    It "leaves plain text unbolded" {
        $cmdline_param_OUTPUT_FORMAT = $TEXT_STYLE
        $report = "$SECTION_ITEM_MARKER SYSTEM $SECTION_ITEM_MARKER$PHYSICAL_NEWLINE" +
                  "CPU cores${FIELD_LABEL_SEPARATOR}12"
        $result = (Complete-Report $report) -join $PHYSICAL_NEWLINE
        $result | Should -Not -Match '\*\*|<b>'
    }

    It "wraps section headings and field labels in ** for markdown" {
        $cmdline_param_OUTPUT_FORMAT = $MARKDOWN_STYLE
        $report = "$SECTION_ITEM_MARKER SYSTEM $SECTION_ITEM_MARKER$PHYSICAL_NEWLINE" +
                  "CPU cores${FIELD_LABEL_SEPARATOR}12"
        $result = (Complete-Report $report) -join $PHYSICAL_NEWLINE
        $result | Should -Match "\*\*$SECTION_ITEM_MARKER SYSTEM $SECTION_ITEM_MARKER\*\*"
        $result | Should -Match "\*\*CPU cores:\*\* 12"
    }

    It "wraps section headings and field labels in bold tags for html" {
        $cmdline_param_OUTPUT_FORMAT = $HTML_STYLE
        $report = "$SECTION_ITEM_MARKER SYSTEM $SECTION_ITEM_MARKER$PHYSICAL_NEWLINE" +
                  "CPU cores${FIELD_LABEL_SEPARATOR}12"
        $result = (Complete-Report $report) -join $PHYSICAL_NEWLINE
        $result | Should -Match "<b>$SECTION_ITEM_MARKER SYSTEM $SECTION_ITEM_MARKER</b>"
        $result | Should -Match "<b>CPU cores:</b> 12"
    }

    It "does not write a report file when the destination is terminal-only" {
        $cmdline_param_OUTPUT_FORMAT = $TEXT_STYLE
        Complete-Report "CPU cores${FIELD_LABEL_SEPARATOR}12" | Out-Null
        Test-Path "$OUTPUT_FILE_NAME.$TEXT_EXTENSION" | Should -BeFalse
    }

    It "writes a report file when the destination includes file" {
        $cmdline_param_OUTPUT_FORMAT = $TEXT_STYLE
        $cmdline_param_OUTPUT_DESTINATION = $FILE_OUTPUT
        Complete-Report "CPU cores${FIELD_LABEL_SEPARATOR}12" | Out-Null
        $reportPath = "$OUTPUT_FILE_NAME.$TEXT_EXTENSION"
        Test-Path $reportPath | Should -BeTrue
        Get-Content $reportPath -Raw | Should -Match "CPU cores"
    }
}
