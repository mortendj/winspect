function New-Report() {
    Write-FunctionCallLog $PSBoundParameters
    $output = Get-PageHeader "Winspect Report"
    $output += $PHYSICAL_NEWLINE

    # REPORT INFO
    $sectionHeading = "REPORT INFO"
    $lineScriptBlocks = @(
        { "Local time$FIELD_LABEL_SEPARATOR$(Get-LocalTime)" },
        { "User$FIELD_LABEL_SEPARATOR$(Get-UserWithDomain)" },
        { "Winspect version$FIELD_LABEL_SEPARATOR$SCRIPT_VERSION ($VERSION_TIMESTAMP)" },
        { "Running elevated$FIELD_LABEL_SEPARATOR$(if (Invoke-WithErrorHandling -ScriptBlock {Test-AdminRights}) { 'Yes' } else { 'No' })" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # CERTIFICATES (placed early, right after REPORT INFO - expiration is short, time-sensitive
    # information worth surfacing before the larger host identity/network/resources block below)
    $sectionHeading = "CERTIFICATES"
    $lineScriptBlocks = @(
        { "Certificate expirations$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-CertificateExpirations})" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # ADDITIONAL CERTIFICATE (only appears if -certificateFilePath or -certificateHostname was
    # supplied - covers certificates an application manages as a file or live endpoint rather than
    # through the Windows certificate store, which the CERTIFICATES section above can't see)
    $sectionHeading = $cmdline_param_CERTIFICATE_SECTION_LABEL
    if ($cmdline_param_CERTIFICATE_FILE_PATH -ne "" -or $cmdline_param_CERTIFICATE_HOSTNAME -ne "") {
        $lineScriptBlocks = @(
            { "$(Invoke-WithErrorHandling -ScriptBlock {Get-AdditionalCertificateInfo $cmdline_param_CERTIFICATE_FILE_PATH $cmdline_param_CERTIFICATE_HOSTNAME})" }
        )
        $output += New-SectionOutput $sectionHeading $lineScriptBlocks
    }

    # HOST IDENTITY
    $sectionHeading = "HOST IDENTITY"
    $lineScriptBlocks = @(
        { "Hostname$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-HostName})" },
        { "Operating system$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-OperatingSystemVersion})" },
        { "Machine ID$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-MachineId})" },
        { "Virtualization$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-VirtualizationStatus})" },
        { "VMware Tools version$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-VMwareToolsVersion})" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # NETWORK
    $sectionHeading = "NETWORK"
    $lineScriptBlocks = @(
        { "Network adapters$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-NetworkAdapters})" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # SYSTEM RESOURCES (capacity - what the machine has, not how busy it currently is)
    $sectionHeading = "SYSTEM RESOURCES"
    $lineScriptBlocks = @(
        { "CPU cores$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-CpuCapacity})" },
        { "RAM capacity$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-RamCapacity}) GB" },
        { "Disk capacity$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-DiskCapacity})" },
        { "Disk speed$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-DiskSpeed})" },
        { "Disk latency$FIELD_LABEL_SEPARATOR" },
        { "$(Invoke-WithErrorHandling -ScriptBlock {Get-DiskLatency})" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # RESOURCE USAGE (current consumption - a point-in-time snapshot, distinct from capacity above)
    $sectionHeading = "RESOURCE USAGE"
    $lineScriptBlocks = @(
        { "Current CPU load$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-CurrentCpuUsage}) %" },
        { "Current RAM usage$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-CurrentMemoryUsage}) %" }
    )
    $output += New-SectionOutput $sectionHeading $lineScriptBlocks

    # GMSA ACCOUNT (this section only appears if -gmsaAccountName was supplied)
    $sectionHeading = "GMSA ACCOUNT"
    if ($cmdline_param_GMSA_ACCOUNT_NAME -ne "") {
        $lineScriptBlocks = @(
            { "Account name$FIELD_LABEL_SEPARATOR$cmdline_param_GMSA_ACCOUNT_NAME" },
            { "Status$FIELD_LABEL_SEPARATOR$(Invoke-WithErrorHandling -ScriptBlock {Get-GmsaAccountStatus $cmdline_param_GMSA_ACCOUNT_NAME})" }
        )
        $output += New-SectionOutput $sectionHeading $lineScriptBlocks
    }

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
