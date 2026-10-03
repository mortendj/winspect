BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/Certificates.ps1"

    function New-FakeCertificate($commonName, $notAfter, $hasPrivateKey = $true, $issuer = "CN=Test CA", $dnsNames = $null) {
        # Defaults DnsNameList to just the common name - matches every existing test in this file,
        # where the hostname checked always equals the certificate's own common name, so the new
        # SAN check added 2026-10-03 resolves as a clean match unless a test explicitly overrides
        # $dnsNames to exercise a mismatch.
        if ($null -eq $dnsNames) { $dnsNames = @($commonName) }
        $dnsNameList = @($dnsNames | ForEach-Object { [pscustomobject]@{ Unicode = $_ } })
        $certificate = [pscustomobject]@{ NotAfter = $notAfter; HasPrivateKey = $hasPrivateKey; Issuer = $issuer; DnsNameList = $dnsNameList }
        # GetNameInfo needs to be a closure over $commonName, since by the time it's actually
        # invoked (inside Get-CertificateExpirations), this function's own scope is long gone.
        $getNameInfo = { param($nameType, $forIssuer) return $commonName }.GetNewClosure()
        $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value $getNameInfo
        return $certificate
    }
}

Describe "Get-CertificateExpirationText" {
    It "reports days remaining for a certificate that hasn't expired yet" {
        $certificate = New-FakeCertificate "example.com" (Get-Date).AddDays(30)
        Get-CertificateExpirationText $certificate | Should -Match "^expires \d{4}-\d{2}-\d{2} \(\d+ days\)$"
    }

    It "flags an already-expired certificate as EXPIRED rather than a negative day count" {
        $certificate = New-FakeCertificate "old.example.com" (Get-Date).AddDays(-10)
        Get-CertificateExpirationText $certificate | Should -Match "^expires \d{4}-\d{2}-\d{2} \(EXPIRED \d+ days ago\)$"
    }
}

Describe "Get-AdditionalCertificateInfo" {
    # Mocks Winspect's own wrapper functions (Get-CertificateFromFile/Get-CertificateFromHostname),
    # not X509Certificate2/TcpClient/SslStream directly - those are the real I/O boundary, only
    # exercised for real against an actual file or live endpoint.

    It "checks the file when only a certificate file path is supplied" {
        $certificate = New-FakeCertificate "from-file.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromFile { $certificate }
        Mock Get-CertificateFromHostname { throw "should not be called" }

        $result = Get-AdditionalCertificateInfo "C:\some\cert.crt" ""

        $result | Should -Match "from-file\.example\.com"
        $result | Should -Match "checked via file$"
    }

    It "checks the hostname when only a hostname is supplied" {
        $certificate = New-FakeCertificate "from-host.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromFile { throw "should not be called" }
        Mock Get-CertificateFromHostname { $certificate }

        $result = Get-AdditionalCertificateInfo "" "from-host.example.com:443"

        $result | Should -Match "from-host\.example\.com"
        $result | Should -Match "checked live via HTTPS$"
    }

    It "checks both and reports a clean match when the live and file certificates have the same issuer" {
        $liveCertificate = New-FakeCertificate "engine.example.com" (Get-Date).AddDays(30) -issuer "CN=Real CA"
        $fileCertificate = New-FakeCertificate "engine.example.com" (Get-Date).AddDays(30) -issuer "CN=Real CA"
        Mock Get-CertificateFromHostname { $liveCertificate }
        Mock Get-CertificateFromFile { $fileCertificate }

        $result = Get-AdditionalCertificateInfo "C:\some\cert.crt" "engine.example.com:443"

        $result | Should -Match "engine\.example\.com"
        $result | Should -Match "checked live via HTTPS \(issuer matches the certificate file\)$"
        $result | Should -Not -Match "mismatch"
    }

    It "flags a mismatch when the live and file certificates have different issuers (e.g. a TLS-inspecting proxy)" {
        # Regression test for a real finding on a customer host: a local security proxy (ESET SSL
        # Filter) re-signed the live-fetched certificate with its own issuer, while the actual
        # gateway certificate file was signed by a real CA - same expiration date on both, so
        # comparing only expiration would have missed this entirely.
        $liveCertificate = New-FakeCertificate "engine.example.com" (Get-Date).AddDays(30) -issuer "CN=ESET SSL Filter CA"
        $fileCertificate = New-FakeCertificate "engine.example.com" (Get-Date).AddDays(30) -issuer "CN=Real CA"
        Mock Get-CertificateFromHostname { $liveCertificate }
        Mock Get-CertificateFromFile { $fileCertificate }

        $result = Get-AdditionalCertificateInfo "C:\some\cert.crt" "engine.example.com:443"

        $result | Should -Match "Certificate mismatch"
        $result | Should -Match "Live \(HTTPS\)$([regex]::Escape($FIELD_LABEL_SEPARATOR))engine\.example\.com.*issued by CN=ESET SSL Filter CA"
        $result | Should -Match "File$([regex]::Escape($FIELD_LABEL_SEPARATOR))engine\.example\.com.*issued by CN=Real CA"
    }

    It "falls back to the file, and says so, when the live hostname check fails and a file is also given" {
        $certificate = New-FakeCertificate "from-file.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromHostname { throw "connection refused" }
        Mock Get-CertificateFromFile { $certificate }

        $result = Get-AdditionalCertificateInfo "C:\some\cert.crt" "unreachable.example.com:443"

        $result | Should -Match "from-file\.example\.com"
        $result | Should -Match "checked via file - live HTTPS check against 'unreachable\.example\.com:443' failed: connection refused"
    }

    It "falls back to the live result, and says so, when the file check fails and a hostname is also given" {
        $certificate = New-FakeCertificate "from-host.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromHostname { $certificate }
        Mock Get-CertificateFromFile { throw "file not found" }

        $result = Get-AdditionalCertificateInfo "C:\missing\cert.crt" "from-host.example.com:443"

        $result | Should -Match "from-host\.example\.com"
        $result | Should -Match "checked live via HTTPS - certificate file check failed: file not found"
    }

    It "surfaces both failures as an error when neither the live check nor the file check succeeds" {
        Mock Get-CertificateFromHostname { throw "connection refused" }
        Mock Get-CertificateFromFile { throw "file not found" }

        { Get-AdditionalCertificateInfo "C:\missing\cert.crt" "unreachable.example.com:443" } | Should -Throw "*connection refused*file not found*"
    }

    It "flags it when the configured hostname is missing from the certificate's Subject Alternative Names" {
        # Regression test for a real finding on a production host: a self-signed certificate had
        # SAN entries for the bare hostname and bare domain separately, but never the one combined
        # FQDN actually configured as the gateway hostname - TLS clients fail to validate it even
        # though the cert/key pair itself is otherwise fine.
        $certificate = New-FakeCertificate "gw01" (Get-Date).AddDays(30) -dnsNames @("gw01", "example.com")
        Mock Get-CertificateFromHostname { throw "connection refused" }
        Mock Get-CertificateFromFile { $certificate }

        $result = Get-AdditionalCertificateInfo "C:\some\cert.crt" "gw01.example.com:443"

        $result | Should -Match "checked via file - live HTTPS check against 'gw01\.example\.com:443' failed: connection refused"
        $result | Should -Match "hostname 'gw01\.example\.com' NOT found in Subject Alternative Names \(gw01, example\.com\)"
    }

    It "stays silent about Subject Alternative Names when the hostname is found (the common case)" {
        $certificate = New-FakeCertificate "from-host.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromFile { throw "should not be called" }
        Mock Get-CertificateFromHostname { $certificate }

        $result = Get-AdditionalCertificateInfo "" "from-host.example.com:443"

        $result | Should -Match "checked live via HTTPS$"
        $result | Should -Not -Match "Subject Alternative Names"
    }

    It "flags a SAN mismatch on the live certificate even when the live and file certificates otherwise match" {
        $liveCertificate = New-FakeCertificate "engine.example.com" (Get-Date).AddDays(30) -issuer "CN=Real CA" -dnsNames @("engine.example.com")
        $fileCertificate = New-FakeCertificate "engine.example.com" (Get-Date).AddDays(30) -issuer "CN=Real CA"
        Mock Get-CertificateFromHostname { $liveCertificate }
        Mock Get-CertificateFromFile { $fileCertificate }

        $result = Get-AdditionalCertificateInfo "C:\some\cert.crt" "wrong-hostname.example.com:443"

        $result | Should -Match "hostname 'wrong-hostname\.example\.com' NOT found in Subject Alternative Names \(engine\.example\.com\)"
    }
}

Describe "Get-CertificateExpirations" {
    # Every mock here returns via `return ,(...)`, deliberately matching the exact comma-wrapped
    # return shape Write-ReturnValue produces in the real Get-LocalMachineCertificates. A mock
    # that just returns `@(...)` as a bare expression would enumerate normally when piped, masking
    # the real bug this suite caught: piping directly from a Write-ReturnValue-returning function
    # makes the whole array look like a single pipeline item to whatever consumes it.

    It "reports that the store is empty rather than an empty line" {
        Mock Get-LocalMachineCertificates { return ,@() }
        Get-CertificateExpirations | Should -Match "No certificates"
    }

    It "excludes certificates without a private key (CA/trust-chain certs, not this host's own)" {
        $trustChainCertificate = New-FakeCertificate "Some Root CA" (Get-Date).AddDays(900) -hasPrivateKey $false
        $ownCertificate = New-FakeCertificate "example.com" (Get-Date).AddDays(30) -hasPrivateKey $true
        Mock Get-LocalMachineCertificates { return ,@($trustChainCertificate, $ownCertificate) }

        $result = Get-CertificateExpirations

        $result | Should -Match "example\.com"
        $result | Should -Not -Match "Some Root CA"
    }

    It "reports days remaining for a certificate that hasn't expired yet" {
        $futureCertificate = New-FakeCertificate "example.com" (Get-Date).AddDays(30)
        Mock Get-LocalMachineCertificates { return ,@($futureCertificate) }

        $result = Get-CertificateExpirations

        $result | Should -Match "example\.com -> expires \d{4}-\d{2}-\d{2} \(\d+ days\)"
        $result | Should -Not -Match "EXPIRED"
    }

    It "flags an already-expired certificate as EXPIRED rather than showing a negative day count" {
        $expiredCertificate = New-FakeCertificate "old.example.com" (Get-Date).AddDays(-10)
        Mock Get-LocalMachineCertificates { return ,@($expiredCertificate) }

        $result = Get-CertificateExpirations

        $result | Should -Match "old\.example\.com -> expires \d{4}-\d{2}-\d{2} \(EXPIRED \d+ days ago\)"
    }

    It "sorts multiple certificates soonest-expiring first" {
        $soonCertificate = New-FakeCertificate "soon.example.com" (Get-Date).AddDays(5)
        $laterCertificate = New-FakeCertificate "later.example.com" (Get-Date).AddDays(100)
        Mock Get-LocalMachineCertificates { return ,@($laterCertificate, $soonCertificate) }

        $result = Get-CertificateExpirations

        $result.IndexOf("soon.example.com") | Should -BeLessThan $result.IndexOf("later.example.com")
    }
}
