function Initialize-OutputFormatLayout($outputFormat) {
    if ($outputFormat -eq $HTML_STYLE) {
        $script:LOGICAL_NEWLINE = "$BR$PHYSICAL_NEWLINE"
        $script:INDENTATION     = "&nbsp;&nbsp;&nbsp;&nbsp;"
        $script:START_HEADING   = "<h2>"
        $script:END_HEADING     = "</h2>"
    } elseif ($outputFormat -eq $MARKDOWN_STYLE) {
        $script:LOGICAL_NEWLINE = $PHYSICAL_NEWLINE
        $script:INDENTATION     = "&nbsp;&nbsp;&nbsp;&nbsp;"
        $script:START_HEADING   = "##"
        $script:END_HEADING     = ""
    } elseif ($outputFormat -eq $TEXT_STYLE) {
        $script:LOGICAL_NEWLINE = $PHYSICAL_NEWLINE
        $script:INDENTATION     = "    "
        $script:START_HEADING   = ""
        $script:END_HEADING     = ""
    }
}

function Get-CapitalizedTitle($title) {
    Write-FunctionCallLog $PSBoundParameters
    $capitalizedTitle = ([System.Globalization.CultureInfo]::GetCultureInfo("en-US")).TextInfo.ToTitleCase($title.ToLower())
    Write-ReturnValue $capitalizedTitle.Replace("And ", "and ").Replace("In ", "in ")
}

function Get-PageHeader($title) {
    Write-FunctionCallLog $PSBoundParameters
    $pageHeader = ""
    if ($cmdline_param_OUTPUT_FORMAT -eq $HTML_STYLE) {
        $pageHeader = "<html><body><h1>$title</h1>$PHYSICAL_NEWLINE"
    }
    Write-ReturnValue $pageHeader
}

function Get-PageFooter() {
    Write-FunctionCallLog $PSBoundParameters
    $pageFooter = ""
    if ($cmdline_param_OUTPUT_FORMAT -eq $HTML_STYLE) {
        $pageFooter = "</body></html>$PHYSICAL_NEWLINE"
    }
    Write-ReturnValue $pageFooter
}

function Get-SectionHeader($title) {
    Write-FunctionCallLog $PSBoundParameters
    $sectionHeader = "$START_HEADING $(Get-CapitalizedTitle $title)$END_HEADING$PHYSICAL_NEWLINE"
    if ($cmdline_param_OUTPUT_FORMAT -eq $TEXT_STYLE) {
        $totalLength = 60
        $numHashes = ($totalLength - $title.Length - 2) / 2
        if ($numHashes -lt 4) {
            Exit-WithErrorMessage "Section title is too long"
        }
        $hashes = '#' * [Math]::Floor($numHashes)
        $paddedTitle = "$hashes $title $hashes"
        if ($paddedTitle.Length -lt $totalLength) {
            $paddedTitle += "#"
        }
        $sectionHeader = $paddedTitle
    }
    Write-ReturnValue $sectionHeader
}

function Test-SectionItemHeading($line) {
    return $line -like "*$SECTION_ITEM_MARKER*"
}

function Test-DataFieldLine($line) {
    if ($line.Length -eq 0) {
        return $false
    } elseif ($NON_FIELD_CHARACTERS -contains ($line.TrimStart())[0]) {
        return $false
    } elseif (-not ($line.Contains($FIELD_LABEL_SEPARATOR))) {
        return $false
    } else {
        return $true
    }
}

function Complete-Report($report) {
    Write-FunctionCallLog $PSBoundParameters $true
    $reportFileExtension = $TEXT_EXTENSION
    $boldStart = ""
    $boldEnd = ""
    if ($cmdline_param_OUTPUT_FORMAT -eq $HTML_STYLE) {
        $reportFileExtension = $HTML_EXTENSION
        $boldStart = "<b>"
        $boldEnd = "</b>"
    } elseif ($cmdline_param_OUTPUT_FORMAT -eq $MARKDOWN_STYLE) {
        $reportFileExtension = $MARKDOWN_EXTENSION
        $boldStart = "**"
        $boldEnd = "**"
    }
    $formattedReport = @()
    $lines = $report -split $PHYSICAL_NEWLINE
    foreach ($line in $lines) {
        if (Test-SectionItemHeading $line) {
            $line = $boldStart + $line + $boldEnd
        } elseif (Test-DataFieldLine $line) {
            $line = $boldStart + $line.Replace($FIELD_LABEL_SEPARATOR, ":$boldEnd ")
        }
        $formattedReport += $line
    }
    $report = $formattedReport -join $PHYSICAL_NEWLINE
    if ($FILE_OUTPUTS -contains $cmdline_param_OUTPUT_DESTINATION) {
        try {
            Invoke-WithRetry { Set-Content -Path "$OUTPUT_FILE_NAME.$reportFileExtension" -Value $report -ErrorAction Stop } "Set-Content"
        } catch {
            Set-Content -Path "$OUTPUT_FILE_NAME.$reportFileExtension" -Value $report -ErrorAction SilentlyContinue
        }
    }
    if ($TERMINAL_OUTPUTS -contains $cmdline_param_OUTPUT_DESTINATION) {
        Write-ReturnValue $formattedReport
    }
}

function Invoke-WithErrorHandling([ScriptBlock]$ScriptBlock) {
    Write-FunctionCallLog $PSBoundParameters
    try {
        $result = & $ScriptBlock
    } catch {
        $result = Get-ErrorOutput $_
        Write-ErrorLog "Exception caught by exception handler: $result" $_
    }
    Write-ReturnValue $result
}

function New-SectionOutput($sectionHeader, $lineScriptBlocks) {
    Write-FunctionCallLog $PSBoundParameters
    $output = (Get-SectionHeader $sectionHeader) + $PHYSICAL_NEWLINE
    if (-not $lineScriptBlocks -is [array]) {
        $lineScriptBlocks = @($lineScriptBlocks)
    }
    foreach ($lineScriptBlock in $lineScriptBlocks) {
        try {
            Write-DebugLog "About to render report line"
            $output += & $lineScriptBlock
        } catch {
            $output += Get-ErrorOutput $_
        }
        $output += $LOGICAL_NEWLINE
    }
    $output += $PHYSICAL_NEWLINE
    Write-ReturnValue $output
}
