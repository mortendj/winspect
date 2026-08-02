# The mockable boundary - GitHub's API requires a User-Agent header or it rejects the request.
function Get-LatestReleaseVersion() {
    Write-FunctionCallLog $PSBoundParameters
    $release = Invoke-RestMethod -Uri $GITHUB_RELEASES_API_URL -TimeoutSec 5 -UserAgent "Winspect"
    Write-ReturnValue ($release.tag_name -replace '^v', '')
}

function Get-UpdateNotice() {
    Write-FunctionCallLog $PSBoundParameters
    # Deliberately never throws: Winspect may run on servers with no outbound internet access at
    # all (or a firewall that blocks it), and a failed update check must never be treated as a
    # failure of the tool itself - it just means no notice gets shown.
    $notice = ""
    try {
        $latestVersion = Get-LatestReleaseVersion
        if ([version]$latestVersion -gt [version]$SCRIPT_VERSION) {
            $notice = "A newer version of Winspect is available: v$latestVersion (you have v$SCRIPT_VERSION). Get it at $GITHUB_RELEASES_URL"
        }
    } catch {
        Write-DebugLog "Update check failed, continuing without a notice: $($_.Exception.Message)"
    }
    Write-ReturnValue $notice
}
