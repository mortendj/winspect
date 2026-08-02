BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/NetworkInfo.ps1"

    function New-FakeAdapterConfiguration($interfaceAlias, $ipAddresses, $networkCategory = $null) {
        $ipv4Address = @($ipAddresses | ForEach-Object { [pscustomobject]@{ IPAddress = $_ } })
        $netProfile = if ($null -ne $networkCategory) { [pscustomobject]@{ NetworkCategory = $networkCategory } } else { $null }
        return [pscustomobject]@{
            InterfaceAlias = $interfaceAlias
            IPv4Address    = $ipv4Address
            NetProfile     = $netProfile
        }
    }
}

Describe "Test-LinkLocalIpAddress" {
    It "recognizes an APIPA address as link-local" {
        Test-LinkLocalIpAddress "169.254.1.1" | Should -BeTrue
    }

    It "does not treat a normal private address as link-local" {
        Test-LinkLocalIpAddress "192.168.1.1" | Should -BeFalse
    }

    It "does not treat a normal address in a different private range as link-local" {
        Test-LinkLocalIpAddress "10.0.0.1" | Should -BeFalse
    }
}

Describe "Get-NetworkAdapters" {
    # Every mock returns via `return ,(...)`, matching the exact shape Write-ReturnValue produces
    # in the real Get-NetworkAdapterConfigurations - a mock returning a bare `@(...)` expression
    # would enumerate normally when consumed, masking the exact bug found in Certificates.ps1.

    It "reports when there are no adapters at all" {
        Mock Get-NetworkAdapterConfigurations { return ,@() }
        Get-NetworkAdapters | Should -Match "No network adapters"
    }

    It "excludes an adapter whose only address is link-local (not actually connected to anything)" {
        $disconnected = New-FakeAdapterConfiguration "Ethernet" @("169.254.1.1")
        Mock Get-NetworkAdapterConfigurations { return ,@($disconnected) }

        Get-NetworkAdapters | Should -Match "No network adapters"
    }

    It "reports an adapter's name, IP address, and network category" {
        $wifi = New-FakeAdapterConfiguration "Wi-Fi" @("192.168.3.55") "Private"
        Mock Get-NetworkAdapterConfigurations { return ,@($wifi) }

        $result = Get-NetworkAdapters

        $result | Should -Match "Wi-Fi -> 192\.168\.3\.55 \(Private\)"
    }

    It "reports 'Unknown' category when the adapter has no network profile" {
        $noProfile = New-FakeAdapterConfiguration "Ethernet" @("10.0.0.5")
        Mock Get-NetworkAdapterConfigurations { return ,@($noProfile) }

        Get-NetworkAdapters | Should -Match "Ethernet -> 10\.0\.0\.5 \(Unknown\)"
    }

    It "shows only the routable address when an adapter has both a link-local and a real address" {
        $mixed = New-FakeAdapterConfiguration "Ethernet" @("169.254.1.1", "10.0.0.5") "Private"
        Mock Get-NetworkAdapterConfigurations { return ,@($mixed) }

        $result = Get-NetworkAdapters

        $result | Should -Match "10\.0\.0\.5"
        $result | Should -Not -Match "169\.254"
    }

    It "reports multiple adapters, excluding the disconnected one" {
        $wifi = New-FakeAdapterConfiguration "Wi-Fi" @("192.168.3.55") "Private"
        $disconnected = New-FakeAdapterConfiguration "Bluetooth" @("169.254.9.9")
        Mock Get-NetworkAdapterConfigurations { return ,@($wifi, $disconnected) }

        $result = Get-NetworkAdapters

        $result | Should -Match "Wi-Fi"
        $result | Should -Not -Match "Bluetooth"
    }
}
