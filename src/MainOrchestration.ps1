function Invoke-Inspections() {
    Write-FunctionCallLog $PSBoundParameters
    Write-InfoLog "Starting producing Winspect report"
    $report = New-Report
    $report = Complete-Report $report
    Write-ReturnValue $report
}

function Start-Winspect() {
    if ($cmdline_param_VERSION) {
        $output = $VERSION_STRING
    } else {
        Remove-ExistingLogs
        Write-InfoLog "################### Starting $VERSION_STRING ###################"
        $output = Invoke-Inspections
        Write-InfoLog "################### Tool execution completed ###################"
    }
    return $output
}
