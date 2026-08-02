function Get-NetworkAdapterConfigurations() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue @(Get-NetIPConfiguration)
}

function Test-LinkLocalIpAddress($ipAddress) {
    return $ipAddress.StartsWith("169.254.")
}

function Get-NetworkAdapters() {
    Write-FunctionCallLog $PSBoundParameters
    # Deliberately assigned before use, not piped directly from the function call - piping
    # straight from a Write-ReturnValue-returning function makes the whole array look like one
    # pipeline item instead of enumerating it (see Certificates.ps1 for the full story).
    $adapterConfigurations = Get-NetworkAdapterConfigurations
    $lines = @()
    foreach ($adapterConfiguration in $adapterConfigurations) {
        # 169.254.x.x (APIPA) means "no DHCP server responded" - the adapter is enabled but not
        # actually connected to anything useful, and would just be noise in this report.
        $routableAddresses = @($adapterConfiguration.IPv4Address |
            ForEach-Object { $_.IPAddress } |
            Where-Object { -not (Test-LinkLocalIpAddress $_) })
        if ($routableAddresses.Count -eq 0) {
            continue
        }
        $adapterName = $adapterConfiguration.InterfaceAlias
        $category = if ($adapterConfiguration.NetProfile) { $adapterConfiguration.NetProfile.NetworkCategory } else { "Unknown" }
        $lines += "$INDENTATION$adapterName -> $($routableAddresses -join ", ") ($category)"
    }
    if ($lines.Count -eq 0) {
        $output = "${INDENTATION}No network adapters with a routable IP address found"
    } else {
        $output = "$($lines -join $LOGICAL_NEWLINE)"
    }
    Write-ReturnValue $output
}
