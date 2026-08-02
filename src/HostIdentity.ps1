function Get-HostName() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue ([System.Net.Dns]::GetHostName())
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

function Test-AdminRights() {
    Write-FunctionCallLog $PSBoundParameters
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
    Write-ReturnValue $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
