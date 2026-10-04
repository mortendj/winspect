BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/SystemQuery.ps1"
    . "$PSScriptRoot/../src/HostIdentity.ps1"
}

Describe "Get-HostName" {
    It "returns a non-empty hostname" {
        # No mocking here - this genuinely queries the real machine via .NET's static Dns class,
        # and there's nothing meaningful to fake it with; just confirm it returns something usable.
        # On this test machine it may or may not resolve to a full FQDN (depends on whether it's
        # domain-joined) - that's exactly why this only asserts non-empty rather than a specific
        # format, matching what a real host would actually return either way.
        Get-HostName | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-OperatingSystemVersion" {
    It "formats caption, version, and build number into one readable string" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Caption = "Microsoft Windows 11 Pro"; Version = "10.0.26200"; BuildNumber = "26200" }
        } -ParameterFilter { $className -eq "Win32_OperatingSystem" }

        Get-OperatingSystemVersion | Should -Be "Microsoft Windows 11 Pro (10.0.26200, build 26200)"
    }
}

Describe "Get-MachineId" {
    It "returns the SMBIOS UUID, base64-encoded to match what the licensing service expects" {
        # Regression test: this used to return the bare UUID, which reads better but isn't the
        # value the licensing service's ValidateMachineId actually accepts (it base64-decodes
        # whatever it's given) - confirmed by decoding a real "Machine ID" value from prior tooling
        # during a side-by-side production-host comparison and finding it was
        # base64(UTF8(uuid-string)), not the raw UUID.
        Mock Get-MyWmiObject {
            [pscustomobject]@{ UUID = "CDF27266-0D99-42DB-9685-5AF465383592" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystemProduct" }

        Get-MachineId | Should -Be "Q0RGMjcyNjYtMEQ5OS00MkRCLTk2ODUtNUFGNDY1MzgzNTky"
    }
}

Describe "Get-VirtualizationStatus" {
    It "recognizes a VMware virtual machine" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Manufacturer = "VMware, Inc."; Model = "VMware Virtual Platform" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystem" }

        Get-VirtualizationStatus | Should -Be "Virtual machine (VMware)"
    }

    It "recognizes a Hyper-V virtual machine" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Manufacturer = "Microsoft Corporation"; Model = "Virtual Machine" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystem" }

        Get-VirtualizationStatus | Should -Be "Virtual machine (Hyper-V)"
    }

    It "falls back to bare metal for an unrecognized manufacturer/model" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Manufacturer = "Dell Inc."; Model = "XPS 15 9500" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystem" }

        Get-VirtualizationStatus | Should -Be "Bare metal (or undetected virtualization platform)"
    }
}

Describe "Get-VMwareToolsVersion" {
    It "reads the installed version from the registry when running under VMware" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Manufacturer = "VMware, Inc."; Model = "VMware Virtual Platform" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystem" }
        Mock Get-ItemProperty {
            @(
                [pscustomobject]@{ DisplayName = "Some Other App"; DisplayVersion = "1.0.0" },
                [pscustomobject]@{ DisplayName = "VMware Tools"; DisplayVersion = "12.3.5.22544099" }
            )
        }

        Get-VMwareToolsVersion | Should -Be "12.3.5.22544099"
    }

    It "returns 'Not installed' when running under VMware but no VMware Tools entry is found" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Manufacturer = "VMware, Inc."; Model = "VMware Virtual Platform" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystem" }
        Mock Get-ItemProperty {
            @([pscustomobject]@{ DisplayName = "Some Other App"; DisplayVersion = "1.0.0" })
        }

        Get-VMwareToolsVersion | Should -Be "Not installed"
    }

    It "returns 'N/A' without touching the registry when not running under VMware" {
        Mock Get-MyWmiObject {
            [pscustomobject]@{ Manufacturer = "Microsoft Corporation"; Model = "Virtual Machine" }
        } -ParameterFilter { $className -eq "Win32_ComputerSystem" }
        Mock Get-ItemProperty { throw "should not be called" }

        Get-VMwareToolsVersion | Should -Be "N/A"
    }
}

Describe "Test-AdminRights" {
    It "returns a boolean without throwing" {
        # Whether the test run happens to be elevated varies by environment - only the type
        # and absence of an exception are portable things to assert here.
        { Test-AdminRights } | Should -Not -Throw
        Test-AdminRights | Should -BeOfType [bool]
    }
}
