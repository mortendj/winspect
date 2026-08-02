function Get-LocalMachineCertificates() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue @(Get-ChildItem -Path "Cert:\LocalMachine\My")
}

function Get-CertificateExpirations() {
    Write-FunctionCallLog $PSBoundParameters
    # Certificates without a private key on this machine are trust-chain (CA/root) certs that
    # happen to sit in the Personal store rather than the Root/CA stores - not something this
    # host actually uses or would ever renew, so they'd just be noise here.
    #
    # Deliberately assigned before filtering, not piped directly: Get-LocalMachineCertificates
    # returns its array via Write-ReturnValue's `return ,$returnValue`, which - though needed so
    # a single-item array survives plain assignment - makes a *piped* consumer see the whole
    # array as one item instead of enumerating it, silently defeating the Where-Object filter.
    $certificates = Get-LocalMachineCertificates
    $certificates = @($certificates | Where-Object { $_.HasPrivateKey })
    if ($certificates.Count -eq 0) {
        $output = "${INDENTATION}No certificates with a private key found in the local machine store"
    } else {
        $sortedCertificates = $certificates | Sort-Object -Property NotAfter
        $lines = @()
        foreach ($certificate in $sortedCertificates) {
            $commonName = $certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
            $expirationDateText = $certificate.NotAfter.ToString("yyyy-MM-dd")
            $daysUntilExpiration = (New-TimeSpan -Start (Get-Date) -End $certificate.NotAfter).Days
            if ($daysUntilExpiration -lt 0) {
                $relativeText = "EXPIRED $([math]::Abs($daysUntilExpiration)) days ago"
            } else {
                $relativeText = "$daysUntilExpiration days"
            }
            $lines += "$INDENTATION$commonName -> expires $expirationDateText ($relativeText)"
        }
        $output = "$($lines -join $LOGICAL_NEWLINE)"
    }
    Write-ReturnValue $output
}
