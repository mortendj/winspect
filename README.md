# Winspect

Winspect is a modular PowerShell tool for inspecting and reporting on the state of a Windows
host — hardware capacity, current resource usage, host identity, and (in later releases)
configuration. It reports only on things that are true of any Windows machine, regardless of
what's installed on it, so it's meant to be a reusable foundation rather than a one-off script.

> **Status:** early, actively developed (v0.2.0). The current release covers host identity plus
> CPU, RAM, and disk capacity/usage.

## Features

- **Host identity:** hostname, OS version/build, machine ID (SMBIOS UUID), and virtual-machine
  detection (VMware/Hyper-V/VirtualBox/KVM/QEMU/Xen).
- **Network adapters:** name, IP address, and network category (Public/Private/Domain) for each
  adapter that's actually connected — link-local (APIPA) addresses, which mean an adapter is
  enabled but not connected to anything, are excluded rather than shown as noise.
- **CPU / RAM / disk capacity:** logical core count, RAM capacity, disk capacity and free space
  per fixed drive, plus disk read/write speed and latency (via `winsat` where available, with a
  manual read/write fallback test).
- **Current resource usage:** CPU load and RAM usage, reported separately from capacity since
  they're a point-in-time snapshot rather than a fixed property of the machine.
- **Certificate expirations:** certificates this host actually uses (has a private key for),
  soonest-expiring first, showing both the expiration date and days remaining (or how long ago
  it expired) — trust-chain/CA certificates that happen to share the store are excluded.
- **Report context:** local time, current user, script version, and whether the session is
  running elevated (relevant since disk performance testing needs it).
- **Output formats:** plain text, Markdown, or HTML.
- **Output destinations:** terminal, a report file, or both.
- **Structured logging:** off by default, configurable up to trace-level detail, written
  alongside the script.
- **File-based parameters:** defaults can be set in a plain text file instead of always
  passing command-line switches.

## Requirements

- Windows, with Windows PowerShell 5.1 or PowerShell 7+.
- Run elevated (as Administrator) to get real disk speed/latency numbers — `winsat` and the
  manual disk write test both require it. Without elevation, those fields report as `-`
  rather than failing.

## Usage

```powershell
# Default: plain text report, printed to the terminal and saved to winspect-report.txt
.\Invoke-Winspect.ps1

# Markdown report, skip the slower disk performance tests
.\Invoke-Winspect.ps1 -outputFormat markdown -skipDiskPerformanceMeasurements

# HTML report, file only
.\Invoke-Winspect.ps1 -outputFormat html -outputDestination file

# Verbose troubleshooting log
.\Invoke-Winspect.ps1 -logLevel debug

# Just print the version and exit
.\Invoke-Winspect.ps1 -version
```

| Parameter | Values | Default | Description |
|---|---|---|---|
| `-outputFormat` | `text`, `markdown`, `html` | `text` | Report style. |
| `-outputDestination` | `terminal`, `file`, `both` | `both` | Where the report goes. |
| `-logLevel` | `trace`, `debug`, `info`, `warning`, `error`, `off` | `off` | Logging verbosity. |
| `-skipDiskPerformanceMeasurements` | switch | off | Skip the slower disk speed/latency tests. |
| `-parametersFile` | path | none | A file of `name value` pairs to use as defaults; command-line values still win. |
| `-version` | switch | off | Print the version and exit. |

### Parameters file format

One `name value` pair per line, blank lines and lines starting with `#` are ignored:

```
outputFormat markdown
skipDiskPerformanceMeasurements true
```

## Sample output

```
####################### REPORT INFO ########################
Local time: 2026-08-02 10:44:26
User: CONTOSO-SRV01\admin
Script version: Winspect v. 0.2.0 (2026-08-02)
Running elevated: Yes

###################### HOST IDENTITY #######################
Hostname: CONTOSO-SRV01
Operating system: Microsoft Windows Server 2022 Standard (10.0.20348, build 20348)
Machine ID: CDF27266-0D99-42DB-9685-5AF465383592
Virtualization: Bare metal (or undetected virtualization platform)

######################### NETWORK ##########################
Network adapters:
    Ethernet0 -> 10.0.1.15 (DomainAuthenticated)

##################### SYSTEM RESOURCES #####################
CPU cores: 12
RAM capacity: 16 GB
Disk capacity:
    C: -> 352.7 GB / 454.9 GB
Disk speed:
    C: -> 352.12 (RR), 1729.46 (RS), 1637.59 (WS), 383.60 (WF), 578.72 (RF)
Disk latency:
    C: -> 0.671 ms

###################### RESOURCE USAGE ######################
Current CPU load: 17 %
Current RAM usage: 82.7 %

####################### CERTIFICATES #######################
Certificate expirations:
    old.contoso-srv01.local -> expires 2022-08-06 (EXPIRED 1456 days ago)
    contoso-srv01.local -> expires 2028-12-31 (882 days)
```

## Project layout

```
Invoke-Winspect.ps1      entry point: parameter declarations, dot-sources src/, kicks off the run
src/
  Constants.ps1          version info, output format/destination settings, layout constants
  Logging.ps1            file logging, log levels, script termination helpers
  Parameters.ps1         merges command-line, parameters-file, and default values
  Utilities.ps1          general helpers: timestamps, external command invocation, retry logic
  SystemQuery.ps1        CIM/WMI query helper
  HostIdentity.ps1       hostname, OS version, machine ID, VM detection, admin-rights check
  NetworkInfo.ps1        network adapters (excludes link-local/disconnected ones)
  CpuMemoryInfo.ps1      CPU and RAM capacity/usage
  DiskInfo.ps1           disk capacity, speed, latency
  Certificates.ps1       certificate expirations from the local machine store
  ReportFormatting.ps1   page/section headers, bold-formatting, report post-processing
  ReportBuilder.ps1      assembles the report sections
  MainOrchestration.ps1  top-level run sequence
```

## Running tests

Tests use [Pester](https://pester.dev/) 5.x:

```powershell
Invoke-Pester -Path .\Tests
```

The suite is layered: plain unit tests for pure functions (formatting, parsing), tests that mock
only the real system-query boundary (`Get-MyWmiObject`, `Invoke-ExternalCommand`) and run the
actual logic on top, tests that assemble a real report from mocked leaf data to check the
formatting/bolding pipeline end-to-end, and a final smoke test that runs the real entry point
with no mocks at all, asserting on output shape rather than exact values.

## Contributing

This is an early-stage personal project, but issues and pull requests are welcome.

## Author

Morten Johnsen — [github.com/mortendj](https://github.com/mortendj)

## License

[MIT](LICENSE)
