function Test-DomainJoined() {
    Write-FunctionCallLog $PSBoundParameters
    $computerSystem = Get-MyWmiObject Win32_ComputerSystem
    Write-ReturnValue $computerSystem.PartOfDomain
}

function Test-ActiveDirectoryModuleAvailable() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue ($null -ne (Get-Module -ListAvailable -Name ActiveDirectory))
}

# Get-ADServiceAccount/Test-ADServiceAccount's -Identity only resolves a bare sAMAccountName,
# not a "DOMAIN\name" form - confirmed on a real domain-joined host, where the domain-qualified
# form failed with "Cannot find an object with identity" while the bare name succeeded for the
# same account. Stripping any NetBIOS domain prefix here lets both forms work the same way,
# since users naturally type the qualified form.
function Get-SamAccountNameWithoutDomainPrefix($accountName) {
    Write-FunctionCallLog $PSBoundParameters
    $parts = $accountName -split '\\', 2
    if ($parts.Length -eq 2) {
        Write-ReturnValue $parts[1]
    } else {
        Write-ReturnValue $accountName
    }
}

# Thin wrappers around the real ActiveDirectory module cmdlets - the mockable boundary, same
# pattern as Get-MyWmiObject. Not unit-tested directly, since Get-ADServiceAccount/
# Test-ADServiceAccount don't exist as commands at all unless RSAT is installed; exercised for
# real only on a domain-joined host with the module present.
function Get-GmsaAccount($gmsaAccountName) {
    Write-FunctionCallLog $PSBoundParameters
    $identity = Get-SamAccountNameWithoutDomainPrefix $gmsaAccountName
    try {
        Write-ReturnValue (Get-ADServiceAccount -Identity $identity -ErrorAction Stop)
    } catch {
        # Deliberately not narrowed to a specific "not found" exception type - without a real AD
        # environment to verify the exact type name against, guessing wrong here would mean this
        # never matches and every lookup falls through uncaught instead. Logging the real message
        # is the safe fix instead of guessing at cause.
        Write-DebugLog "Get-ADServiceAccount failed for '$identity': $($_.Exception.Message)"
        Write-ReturnValue $null
    }
}

function Test-GmsaAccountUsableByThisHost($gmsaAccountName) {
    Write-FunctionCallLog $PSBoundParameters
    $identity = Get-SamAccountNameWithoutDomainPrefix $gmsaAccountName
    Write-ReturnValue (Test-ADServiceAccount -Identity $identity)
}

function Get-GmsaAccountStatus($gmsaAccountName) {
    Write-FunctionCallLog $PSBoundParameters
    if (-not (Test-DomainJoined)) {
        $output = "This host is not domain-joined - gMSA accounts do not apply"
    } elseif (-not (Test-ActiveDirectoryModuleAvailable)) {
        $output = "ActiveDirectory module not installed - cannot verify gMSA account '$gmsaAccountName'"
    } else {
        $account = Get-GmsaAccount $gmsaAccountName
        if ($null -eq $account) {
            $output = "Account '$gmsaAccountName' not found in Active Directory"
        } elseif (Test-GmsaAccountUsableByThisHost $gmsaAccountName) {
            $output = "Account '$gmsaAccountName' exists and can be used by this host"
        } else {
            $output = "Account '$gmsaAccountName' exists but cannot be used by this host " +
                       "(check group membership, or whether this host has been rebooted since being added)"
        }
    }
    Write-ReturnValue $output
}
