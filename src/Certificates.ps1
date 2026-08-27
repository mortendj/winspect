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

function Get-CertificateSummaryLine($certificate, $checkedVia) {
    Write-FunctionCallLog $PSBoundParameters
    $commonName = $certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    Write-ReturnValue "$commonName -> $(Get-CertificateExpirationText $certificate) - $checkedVia"
}

function Get-CertificateComparisonText($liveCertificate, $fileCertificate) {
    Write-FunctionCallLog $PSBoundParameters
    if ($liveCertificate.Issuer -eq $fileCertificate.Issuer) {
        Write-ReturnValue (Get-CertificateSummaryLine $liveCertificate "checked live via HTTPS (issuer matches the certificate file)")
    } else {
        # A live-vs-file issuer mismatch is a real, actionable signal - most commonly a TLS-
        # inspecting proxy (corporate antivirus/firewall) re-signing outbound HTTPS traffic on
        # this host, which silently makes the live check see a different certificate than what a
        # real external client actually gets. Confirmed on a real customer host: the live check
        # returned an "ESET SSL Filter CA"-issued certificate, not the real one from the file -
        # expiration dates happened to match (these proxies often preserve them), which would have
        # hidden the mismatch entirely if only the expiration were compared instead of the issuer.
        $liveCommonName = $liveCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        $fileCommonName = $fileCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        $lines = @(
            "Certificate mismatch (possible TLS interception, e.g. a corporate security proxy) - the certificate served live via HTTPS does not match the certificate file",
            "Live (HTTPS)$FIELD_LABEL_SEPARATOR$liveCommonName -> $(Get-CertificateExpirationText $liveCertificate), issued by $($liveCertificate.Issuer)",
            "File$FIELD_LABEL_SEPARATOR$fileCommonName -> $(Get-CertificateExpirationText $fileCertificate), issued by $($fileCertificate.Issuer)"
        )
        Write-ReturnValue ($lines -join $LOGICAL_NEWLINE)
    }
}

function Get-AdditionalCertificateInfo($certificateFilePath, $certificateHostname) {
    Write-FunctionCallLog $PSBoundParameters
    # Both are checked whenever both are given, not just the live one with the file as a fallback -
    # a live-only check can't detect a host where a local TLS-inspecting proxy silently substitutes
    # its own certificate for outbound HTTPS (see Get-CertificateComparisonText), and only checking
    # both together can surface that.
    # Deliberately not named $liveCertificate/$fileCertificate - Pester's Mock scriptblocks for
    # Get-CertificateFromHostname/Get-CertificateFromFile resolve free variable references via
    # PowerShell's dynamic scoping, which found *this function's own* (still-null-at-call-time)
    # local variable instead of the test's intended fixture when both used that exact name -
    # confirmed by a real test failure this caused. See the identical lesson already documented in
    # [[project_ayfieinspector]]'s SagaCertificateInfo.ps1 history - the general rule is: never
    # reuse a variable name between a test fixture and the function under test.
    $resolvedLiveCertificate = $null
    $resolvedFileCertificate = $null
    $liveCheckFailureReason = $null
    $fileCheckFailureReason = $null

    if ($certificateHostname -ne "") {
        try {
            $resolvedLiveCertificate = Get-CertificateFromHostname $certificateHostname
        } catch {
            $liveCheckFailureReason = $_.Exception.Message
            Write-WarningLog "Live HTTPS certificate check against '$certificateHostname' failed: $liveCheckFailureReason"
        }
    }

    if ($certificateFilePath -ne "") {
        try {
            $resolvedFileCertificate = Get-CertificateFromFile $certificateFilePath
        } catch {
            $fileCheckFailureReason = $_.Exception.Message
            Write-WarningLog "Certificate file check against '$certificateFilePath' failed: $fileCheckFailureReason"
        }
    }

    if ($null -ne $resolvedLiveCertificate -and $null -ne $resolvedFileCertificate) {
        Write-ReturnValue (Get-CertificateComparisonText $resolvedLiveCertificate $resolvedFileCertificate)
    } elseif ($null -ne $resolvedLiveCertificate) {
        $checkedVia = "checked live via HTTPS"
        if ($null -ne $fileCheckFailureReason) {
            $checkedVia += " - certificate file check failed: $fileCheckFailureReason"
        }
        Write-ReturnValue (Get-CertificateSummaryLine $resolvedLiveCertificate $checkedVia)
    } elseif ($null -ne $resolvedFileCertificate) {
        $checkedVia = "checked via file"
        if ($null -ne $liveCheckFailureReason) {
            $checkedVia += " - live HTTPS check against '$certificateHostname' failed: $liveCheckFailureReason"
        }
        Write-ReturnValue (Get-CertificateSummaryLine $resolvedFileCertificate $checkedVia)
    } else {
        # Neither check produced a certificate - surface a failure rather than letting this
        # section silently disappear.
        $failureReasons = @($liveCheckFailureReason, $fileCheckFailureReason) | Where-Object { $_ }
        throw ($failureReasons -join "; ")
    }
}
