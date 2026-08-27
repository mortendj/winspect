function Get-HostName() {
    Write-FunctionCallLog $PSBoundParameters
    # Resolved to the FQDN, not just the short hostname - confirmed as a real regression across
    # multiple real customer hosts (e.g. "AyfieSearch03" vs the actually useful
    # "AyfieSearch03.oslo.ngi.no"). Falls back to the short name unchanged on a host with no
    # resolvable domain suffix (a workgroup machine), since GetHostEntry simply returns the same
    # name it was given in that case - nothing to catch, this never throws for that reason.
    Write-ReturnValue ([System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).HostName)
}

function Get-OperatingSystemVersion() {
    Write-FunctionCallLog $PSBoundParameters
    $operatingSystem = Get-MyWmiObject Win32_OperatingSystem
    Write-ReturnValue "$($operatingSystem.Caption) ($($operatingSystem.Version), build $($operatingSystem.BuildNumber))"
}

function Get-MachineId() {
    Write-FunctionCallLog $PSBoundParameters
    $computerSystemProduct = Get-MyWmiObject Win32_ComputerSystemProduct
    Write-ReturnValue $computerSystemProduct.UUID
}

function Get-VirtualizationStatus() {
    Write-FunctionCallLog $PSBoundParameters
    $computerSystem = Get-MyWmiObject Win32_ComputerSystem
    $signature = "$($computerSystem.Manufacturer) $($computerSystem.Model)"
    $match = $VM_SIGNATURES | Where-Object { $signature -match $_.Pattern } | Select-Object -First 1
    if ($match) {
        Write-ReturnValue "Virtual machine ($($match.Platform))"
    } else {
        Write-ReturnValue "Bare metal (or undetected virtualization platform)"
    }
}

function Get-VMwareToolsVersion() {
    Write-FunctionCallLog $PSBoundParameters
    # Registry-based, not the Win32_Product WMI query some tools use to get this - that class is
    # known to trigger a reconfiguration pass over every MSI-installed package on the machine,
    # which can hang for minutes on a busy host. The registry uninstall keys expose the same
    # version info without touching MSI at all.
    if ((Get-VirtualizationStatus) -like "*VMware*") {
        $vmwareToolsVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "VMware Tools*" } |
            Select-Object -ExpandProperty DisplayVersion -First 1
        if ($vmwareToolsVersion) {
            Write-ReturnValue $vmwareToolsVersion
        } else {
            Write-ReturnValue "Not installed"
        }
    } else {
        Write-ReturnValue "N/A"
    }
}

function Test-AdminRights() {
    Write-FunctionCallLog $PSBoundParameters
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
    Write-ReturnValue $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
