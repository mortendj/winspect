BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/SystemQuery.ps1"
    . "$PSScriptRoot/../src/GmsaInfo.ps1"
}

Describe "Test-DomainJoined" {
    It "returns true when the computer system reports it is part of a domain" {
        Mock Get-MyWmiObject { [pscustomobject]@{ PartOfDomain = $true } } -ParameterFilter { $className -eq "Win32_ComputerSystem" }
        Test-DomainJoined | Should -BeTrue
    }

    It "returns false when the computer system is not part of a domain" {
        Mock Get-MyWmiObject { [pscustomobject]@{ PartOfDomain = $false } } -ParameterFilter { $className -eq "Win32_ComputerSystem" }
        Test-DomainJoined | Should -BeFalse
    }
}

Describe "Get-SamAccountNameWithoutDomainPrefix" {
    It "strips a NetBIOS domain prefix when one is present" {
        Get-SamAccountNameWithoutDomainPrefix "adi\adi-SvcLocator$" | Should -Be "adi-SvcLocator$"
    }

    It "returns the name unchanged when there is no domain prefix" {
        Get-SamAccountNameWithoutDomainPrefix "adi-SvcLocator$" | Should -Be "adi-SvcLocator$"
    }

    It "only splits on the first backslash" {
        Get-SamAccountNameWithoutDomainPrefix "adi\sub\adi-SvcLocator$" | Should -Be "sub\adi-SvcLocator$"
    }
}

Describe "Test-ActiveDirectoryModuleAvailable" {
    It "returns true when the ActiveDirectory module is listed as available" {
        Mock Get-Module { [pscustomobject]@{ Name = "ActiveDirectory" } } -ParameterFilter { $ListAvailable -and $Name -eq "ActiveDirectory" }
        Test-ActiveDirectoryModuleAvailable | Should -BeTrue
    }

    It "returns false when the ActiveDirectory module is not installed" {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq "ActiveDirectory" }
        Test-ActiveDirectoryModuleAvailable | Should -BeFalse
    }
}

Describe "Get-GmsaAccountStatus" {
    # Mocks the function's own wrapper functions (Get-GmsaAccount, Test-GmsaAccountUsableByThisHost),
    # not the raw Get-ADServiceAccount/Test-ADServiceAccount cmdlets - those don't exist as commands
    # at all unless RSAT's ActiveDirectory module is installed, so there's nothing to mock on a
    # machine without it. Real AD interaction is exercised only on an actual domain-joined host.

    It "reports that gMSA doesn't apply when the host isn't domain-joined" {
        Mock Test-DomainJoined { $false }

        Get-GmsaAccountStatus "svc-test" | Should -Match "not domain-joined"
    }

    It "reports the ActiveDirectory module is missing when the host is domain-joined but lacks it" {
        Mock Test-DomainJoined { $true }
        Mock Test-ActiveDirectoryModuleAvailable { $false }

        Get-GmsaAccountStatus "svc-test" | Should -Match "ActiveDirectory module not installed"
    }

    It "reports the account was not found when it doesn't exist in Active Directory" {
        Mock Test-DomainJoined { $true }
        Mock Test-ActiveDirectoryModuleAvailable { $true }
        Mock Get-GmsaAccount { $null }

        Get-GmsaAccountStatus "svc-test" | Should -Match "not found in Active Directory"
    }

    It "reports the account is usable when it exists and this host can retrieve it" {
        Mock Test-DomainJoined { $true }
        Mock Test-ActiveDirectoryModuleAvailable { $true }
        Mock Get-GmsaAccount { [pscustomobject]@{ Name = "svc-test" } }
        Mock Test-GmsaAccountUsableByThisHost { $true }

        Get-GmsaAccountStatus "svc-test" | Should -Match "exists and can be used by this host"
    }

    It "reports the account is not usable when it exists but this host cannot retrieve it" {
        Mock Test-DomainJoined { $true }
        Mock Test-ActiveDirectoryModuleAvailable { $true }
        Mock Get-GmsaAccount { [pscustomobject]@{ Name = "svc-test" } }
        Mock Test-GmsaAccountUsableByThisHost { $false }

        Get-GmsaAccountStatus "svc-test" | Should -Match "exists but cannot be used by this host"
    }
}
