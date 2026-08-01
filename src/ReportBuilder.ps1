function New-Report() {
    Write-FunctionCallLog $PSBoundParameters
    $output = Get-PageHeader "Winspect Report"
    $output += $PHYSICAL_NEWLINE

    # REPORT INFO
    $sectionHeading = "REPORT INFO"
    $lineScriptBlocks = @(
        { "Local time$FIELD_LABEL_SEPARATOR$(Get-LocalTime)" },
        { "User$FIELD_LABEL_SEPARATOR$(Get-UserWithDomain)" },
        { "Script version$FIELD_LABEL_SEPARATOR$VERSION_STRING" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # SYSTEM RESOURCES
    $sectionHeading = "SYSTEM RESOURCES"
    $lineScriptBlocks = @(
        { "CPU cores$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-CpuCapacity})" },
        { "Current CPU load$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-CurrentCpuUsage}) %" },
        { "RAM capacity$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-RamCapacity}) GB" },
        { "Current RAM usage$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-CurrentMemoryUsage}) %" },
        { "Disk capacity$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-DiskCapacity})" },
        { "Disk speed$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-DiskSpeed})" },
        { "Disk latency$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-DiskLatency})" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # FILE WRITE ERRORS (this section only appears if indeed there are file write errors)
    $sectionHeading = "FILE WRITE ERRORS"
    $anyFileWriteErrors = $script:FileWriteErrorCounts.Values | Where-Object { $_ -gt 0 }
    if ($anyFileWriteErrors) {
        $lineScriptBlocks = $script:FileWriteErrorCounts.GetEnumerator() | ForEach-Object {
            $errorType = $_.Key
            $errorCount = $_.Value
            { "$errorType ($errorCount)" }.GetNewClosure()
        }
        $output += New-SectionOutput $sectionHeading $lineScriptBlocks
    }

    $output += Get-PageFooter
    Write-ReturnValue $output
}
