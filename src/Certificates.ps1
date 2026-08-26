function Get-LocalMachineCertificates() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue @(Get-ChildItem -Path "Cert:\LocalMachine\My")
}

function Get-CertificateExpirationText($certificate) {
    Write-FunctionCallLog $PSBoundParameters
    $expirationDateText = $certificate.NotAfter.ToString("yyyy-MM-dd")
    $daysUntilExpiration = (New-TimeSpan -Start (Get-Date) -End $certificate.NotAfter).Days
    if ($daysUntilExpiration -lt 0) {
        $relativeText = "EXPIRED $([math]::Abs($daysUntilExpiration)) days ago"
    } else {
        $relativeText = "$daysUntilExpiration days"
    }
    Write-ReturnValue "expires $expirationDateText ($relativeText)"
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
            $lines += "$INDENTATION$commonName -> $(Get-CertificateExpirationText $certificate)"
        }
        $output = "$($lines -join $LOGICAL_NEWLINE)"
    }
    Write-ReturnValue $output
}

# The local machine store only covers certificates Windows itself knows about (IIS bindings, RDP,
# etc.) - an application that manages its own certificate as a file (very common for containerized
# or cross-platform services) is invisible to that scan entirely, confirmed on a real customer host
# where the actual gateway certificate lived in a file the store scan could never see. These two
# functions let the caller point at such a certificate directly, by file or by live endpoint.

function Get-CertificateFromFile($certificateFilePath) {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificateFilePath))
}

function Get-CertificateFromHostname($hostnameAndPort) {
    Write-FunctionCallLog $PSBoundParameters
    $parts = $hostnameAndPort -split ':', 2
    $hostname = $parts[0]
    $port = if ($parts.Length -eq 2) { [int]$parts[1] } else { 443 }
    $tcpClient = New-Object System.Net.Sockets.TcpClient($hostname, $port)
    try {
        # Deliberately accepts any certificate here, including an expired or otherwise untrusted
        # one - this reads the certificate's own properties rather than making a trust decision,
        # and normal validation would throw before an already-invalid certificate could be read.
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, { $true })
        $sslStream.AuthenticateAsClient($hostname)
        $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
    } finally {
        $tcpClient.Close()
    }
    Write-ReturnValue $certificate
}

function Get-AdditionalCertificateExpiration($certificateFilePath, $certificateHostname) {
    Write-FunctionCallLog $PSBoundParameters
    # Live-over-HTTPS is the real proof that a certificate is actually the one being served, so
    # it's tried first whenever a hostname is given - the file (if also given) is only a fallback
    # for when the real endpoint can't be reached (app down, not installed yet, network path
    # blocked, etc.), and which path actually produced the result below is always stated
    # explicitly rather than silently substituted.
    $resolvedCertificate = $null
    $liveCheckFailureReason = $null
    $checkedVia = $null

    if ($certificateHostname -ne "") {
        try {
            $resolvedCertificate = Get-CertificateFromHostname $certificateHostname
            $checkedVia = "checked live via HTTPS"
        } catch {
            $liveCheckFailureReason = $_.Exception.Message
            Write-WarningLog "Live HTTPS certificate check against '$certificateHostname' failed, falling back to the certificate file if one was given: $liveCheckFailureReason"
        }
    }

    if ($null -eq $resolvedCertificate) {
        if ($certificateFilePath -ne "") {
            $resolvedCertificate = Get-CertificateFromFile $certificateFilePath
            if ($null -ne $liveCheckFailureReason) {
                $checkedVia = "checked via file - live HTTPS check against '$certificateHostname' failed: $liveCheckFailureReason"
            } else {
                $checkedVia = "checked via file"
            }
        } else {
            # No file to fall back to - surface the live-check failure itself rather than letting
            # this section silently disappear.
            throw $liveCheckFailureReason
        }
    }

    $commonName = $resolvedCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    Write-ReturnValue "$commonName -> $(Get-CertificateExpirationText $resolvedCertificate) - $checkedVia"
}
