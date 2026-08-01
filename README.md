# Winspect

Winspect is a modular PowerShell tool for inspecting and reporting on the state of a Windows
host — hardware capacity, current resource usage, and (in later releases) host identity and
configuration. It reports only on things that are true of any Windows machine, regardless of
what's installed on it, so it's meant to be a reusable foundation rather than a one-off script.

> **Status:** early, actively developed (v0.1.0). The current release covers CPU, RAM, and disk
> capacity/usage. See [Roadmap](#roadmap) for what's next.

## Features

- **CPU:** logical core count, current load.
- **RAM:** total capacity, current usage.
- **Disk:** capacity and free space per fixed drive, plus read/write speed and latency
  (via `winsat` where available, with a manual read/write fallback test).
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
Local time: 2026-08-01 10:44:26
User: CONTOSO-SRV01\admin
Script version: Winspect v. 0.1.0 (2026-08-01)

##################### SYSTEM RESOURCES #####################
CPU cores: 12
Current CPU load: 17 %
RAM capacity: 16 GB
Current RAM usage: 82.7 %
Disk capacity:
    C: -> 352.7 GB / 454.9 GB
Disk speed:
    C: -> 352.12 (RR), 1729.46 (RS), 1637.59 (WS), 383.6 (WF), 3578.72 (RF)
Disk latency:
    C: -> 0.671 ms
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
  CpuMemoryInfo.ps1      CPU and RAM capacity/usage
  DiskInfo.ps1           disk capacity, speed, latency
  ReportFormatting.ps1   page/section headers, bold-formatting, report post-processing
  ReportBuilder.ps1      assembles the report sections
  MainOrchestration.ps1  top-level run sequence
```

## Roadmap

- Host identity: hostname, OS version, machine ID, VM vs. bare-metal, admin-rights check.
- Report-type filtering (e.g. verification vs. troubleshooting vs. documentation views).
- Automated tests.

## Contributing

This is an early-stage personal project, but issues and pull requests are welcome.

## Author

Morten Johnsen — [github.com/mortendj](https://github.com/mortendj)

## License

[MIT](LICENSE)
