function Test-DomainJoined() {
    Write-FunctionCallLog $PSBoundParameters
    $computerSystem = Get-MyWmiObject Win32_ComputerSystem
    Write-ReturnValue $computerSystem.PartOfDomain
}

function Test-ActiveDirectoryModuleAvailable() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue ($null -ne (Get-Module -ListAvailable -Name ActiveDirectory))
}

# Thin wrappers around the real ActiveDirectory module cmdlets - the mockable boundary, same
# pattern as Get-MyWmiObject. Not unit-tested directly, since Get-ADServiceAccount/
# Test-ADServiceAccount don't exist as commands at all unless RSAT is installed; exercised for
# real only on a domain-joined host with the module present.
function Get-GmsaAccount($gmsaAccountName) {
    Write-FunctionCallLog $PSBoundParameters
    try {
        Write-ReturnValue (Get-ADServiceAccount -Identity $gmsaAccountName -ErrorAction Stop)
    } catch {
        # Deliberately not narrowed to a specific "not found" exception type - without a real AD
        # environment to verify the exact type name against, guessing wrong here would mean this
        # never matches and every lookup falls through uncaught instead. Logging the real message
        # is the safe fix: it doesn't require guessing, and it's what would have told us straight
        # away whether "adi\adi-SvcLocator$" genuinely doesn't exist or failed for some other
        # reason (bad identity format, permissions, connectivity).
        Write-DebugLog "Get-ADServiceAccount failed for '$gmsaAccountName': $($_.Exception.Message)"
        Write-ReturnValue $null
    }
}

function Test-GmsaAccountUsableByThisHost($gmsaAccountName) {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue (Test-ADServiceAccount -Identity $gmsaAccountName)
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
