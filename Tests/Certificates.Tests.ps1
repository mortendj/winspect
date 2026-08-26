BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/Logging.ps1"
    . "$PSScriptRoot/../src/Utilities.ps1"
    . "$PSScriptRoot/../src/Certificates.ps1"

    function New-FakeCertificate($commonName, $notAfter, $hasPrivateKey = $true) {
        $certificate = [pscustomobject]@{ NotAfter = $notAfter; HasPrivateKey = $hasPrivateKey }
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

Describe "Get-AdditionalCertificateExpiration" {
    # Mocks Winspect's own wrapper functions (Get-CertificateFromFile/Get-CertificateFromHostname),
    # not X509Certificate2/TcpClient/SslStream directly - those are the real I/O boundary, only
    # exercised for real against an actual file or live endpoint.

    It "checks the file when only a certificate file path is supplied" {
        $certificate = New-FakeCertificate "from-file.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromFile { $certificate }
        Mock Get-CertificateFromHostname { throw "should not be called" }

        $result = Get-AdditionalCertificateExpiration "C:\some\cert.crt" ""

        $result | Should -Match "from-file\.example\.com"
        $result | Should -Match "checked via file$"
    }

    It "checks the hostname when only a hostname is supplied" {
        $certificate = New-FakeCertificate "from-host.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromFile { throw "should not be called" }
        Mock Get-CertificateFromHostname { $certificate }

        $result = Get-AdditionalCertificateExpiration "" "from-host.example.com:443"

        $result | Should -Match "from-host\.example\.com"
        $result | Should -Match "checked live via HTTPS$"
    }

    It "prefers the live hostname check over the file when both are supplied and the live check succeeds" {
        $certificate = New-FakeCertificate "from-host.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromHostname { $certificate }
        Mock Get-CertificateFromFile { throw "should not be called" }

        $result = Get-AdditionalCertificateExpiration "C:\some\cert.crt" "from-host.example.com:443"

        $result | Should -Match "from-host\.example\.com"
        $result | Should -Match "checked live via HTTPS$"
    }

    It "falls back to the file, and says so, when the live hostname check fails and a file is also given" {
        $certificate = New-FakeCertificate "from-file.example.com" (Get-Date).AddDays(30)
        Mock Get-CertificateFromHostname { throw "connection refused" }
        Mock Get-CertificateFromFile { $certificate }

        $result = Get-AdditionalCertificateExpiration "C:\some\cert.crt" "unreachable.example.com:443"

        $result | Should -Match "from-file\.example\.com"
        $result | Should -Match "checked via file - live HTTPS check against 'unreachable\.example\.com:443' failed: connection refused"
    }

    It "surfaces the live check failure as an error when it fails and no file was given to fall back to" {
        Mock Get-CertificateFromHostname { throw "connection refused" }
        Mock Get-CertificateFromFile { throw "should not be called" }

        { Get-AdditionalCertificateExpiration "" "unreachable.example.com:443" } | Should -Throw "connection refused"
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
