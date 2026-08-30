############################################################
# Name..............: Winspect                              #
# Author............: Morten Johnsen (github.com/mortendj)  #
############################################################

<#
.SYNOPSIS
Reports on machine-level resources (CPU, RAM, disk capacity/speed/latency) for the host it runs on.

.DESCRIPTION
Winspect is a modular Windows host inspection and reporting tool. This first slice reports only on
generic computer resources that have nothing to do with any specific product installed on the
machine. Product-specific reporting modules can be added later on top of this foundation.

.PARAMETER version
Prints the version of this script and exits.

.PARAMETER outputFormat
Sets the output to text, html or markdown style. Text is the default.

.PARAMETER outputDestination
Determines the destination of the output: terminal, file or both. Both is the default.

.PARAMETER logLevel
Sets the log level to trace, debug, info, warning or error. Off (no logging) is the default.

.PARAMETER skipDiskPerformanceMeasurements
Skips the (comparatively slow) disk speed and latency measurements.

.PARAMETER monitoringPeriodMinutes
How many minutes of CPU/memory samples to average over for the RESOURCE USAGE section, default is
2 - long enough to smooth a momentary spike into a real average, short enough not to meaningfully
slow the script down. Sampling runs in a background job started as soon as parameters are parsed,
so this mostly overlaps with the rest of the report being built rather than adding to it. Raise this
if you deliberately want a longer measurement window.

.PARAMETER monitoringSamplingInSeconds
The time between each CPU/memory sample within the monitoring period, default is 10. Set to 0 to
skip monitoring entirely and fall back to a single instantaneous reading instead.

.PARAMETER parametersFile
Path to a file with parameter name/value pairs (one per line) that act as defaults. Empty lines and
lines starting with '#' are ignored. Command line parameters still take precedence over anything
set in this file.

.PARAMETER gmsaAccountName
Name of a Group Managed Service Account to check. Accepts either a bare sAMAccountName or a
DOMAIN\name form - any NetBIOS domain prefix is stripped before the Active Directory lookup, since
Get-ADServiceAccount's -Identity only resolves the bare name. When supplied, reports whether the
account exists in Active Directory and whether this host can use it. Requires this host to be
domain-joined and have the ActiveDirectory module installed; otherwise reports why it can't check.
Omitted by default, in which case this section doesn't appear at all.

.PARAMETER skipUpdateCheck
Skips checking GitHub for a newer release. The check fails silently anyway (e.g. on hosts with no
outbound internet access), so this is only useful to avoid the network call/delay entirely.

.PARAMETER certificateFilePath
Path to a certificate file to check the expiration of, in addition to the local machine store scan
- useful for certificates an application manages itself as a file rather than through Windows'
certificate store. If -certificateHostname is also supplied, this is only used as a fallback if the
live HTTPS check fails (app down, not installed yet, network path blocked, etc.) - the report
always states which of the two actually produced the result.

.PARAMETER certificateHostname
A hostname (optionally hostname:port, default port 443) to fetch a live TLS certificate from and
check its expiration, in addition to the local machine store scan. Tried first if -certificateFilePath
is also supplied, since a live check is proof of what's actually being served right now rather than
just what a file on disk happens to contain.

.PARAMETER certificateSectionLabel
Section heading to use for the additional certificate check (only relevant when -certificateFilePath
or -certificateHostname is supplied). Defaults to "ADDITIONAL CERTIFICATE" - override this when the
certificate being checked has a more specific name worth calling out in the report (e.g. the name of
the application it belongs to).

.EXAMPLE
.\Invoke-Winspect.ps1
Produces a plain text report to the terminal and to the file "config.txt".

.EXAMPLE
.\Invoke-Winspect.ps1 -outputFormat markdown -skipDiskPerformanceMeasurements
Produces a markdown report, skipping the slow disk performance tests.
#>

[CmdletBinding()]
param (
   [switch]$version,
   [switch]$skipDiskPerformanceMeasurements,

   [Parameter(Mandatory=$false)]
   [double]$monitoringPeriodMinutes = 2,

   [Parameter(Mandatory=$false)]
   [int]$monitoringSamplingInSeconds = 10,

   [Parameter(Mandatory=$false)]
   [ValidateSet("html", "markdown", "text")]
   [string]$outputFormat = "text",

   [Parameter(Mandatory=$false)]
   [ValidateSet("terminal", "file", "both")]
   [string]$outputDestination = "both",

   [Parameter(Mandatory=$false)]
   [ValidateSet("trace", "debug", "info", "warning", "error", "off")]
   [string]$logLevel = "off",

   [Parameter(Mandatory=$false)]
   [string]$parametersFile = "",

   [Parameter(Mandatory=$false)]
   [string]$gmsaAccountName = "",

   [switch]$skipUpdateCheck,

   [Parameter(Mandatory=$false)]
   [string]$certificateFilePath = "",

   [Parameter(Mandatory=$false)]
   [string]$certificateHostname = "",

   [Parameter(Mandatory=$false)]
   [string]$certificateSectionLabel = "ADDITIONAL CERTIFICATE"
)

# The path to this script itself, captured here (top-level of the entry-point file) because
# $PSCommandPath/$PSScriptRoot resolve to the *defining* file when read inside a function -
# capturing it here and passing it along as $SCRIPT_PATH keeps Get-LogFilePath pointed at
# Invoke-Winspect.ps1 itself even though it now lives in dot-sourced files under src/.
$SCRIPT_PATH = $PSCommandPath
$SRC_DIR = Join-Path $PSScriptRoot "src"

. (Join-Path $SRC_DIR "Constants.ps1")
. (Join-Path $SRC_DIR "Logging.ps1")
. (Join-Path $SRC_DIR "Parameters.ps1")
. (Join-Path $SRC_DIR "Utilities.ps1")
. (Join-Path $SRC_DIR "SystemQuery.ps1")
. (Join-Path $SRC_DIR "HostIdentity.ps1")
. (Join-Path $SRC_DIR "NetworkInfo.ps1")
. (Join-Path $SRC_DIR "CpuMemoryInfo.ps1")
. (Join-Path $SRC_DIR "DiskInfo.ps1")
. (Join-Path $SRC_DIR "Certificates.ps1")
. (Join-Path $SRC_DIR "GmsaInfo.ps1")
. (Join-Path $SRC_DIR "UpdateCheck.ps1")
. (Join-Path $SRC_DIR "ReportFormatting.ps1")
. (Join-Path $SRC_DIR "ReportBuilder.ps1")
. (Join-Path $SRC_DIR "MainOrchestration.ps1")

$adjustedParameters = Get-AdjustedParameters $parametersFile
$cmdline_param_VERSION                            = $adjustedParameters["version"]
$cmdline_param_OUTPUT_FORMAT                      = $adjustedParameters["outputFormat"]
$cmdline_param_OUTPUT_DESTINATION                 = $adjustedParameters["outputDestination"]
$cmdline_param_SKIP_DISK_PERFORMANCE_MEASUREMENTS = $adjustedParameters["skipDiskPerformanceMeasurements"]
$cmdline_param_MONITORING_PERIOD_MINUTES          = $adjustedParameters["monitoringPeriodMinutes"]
$cmdline_param_MONITORING_SAMPLING_SECONDS        = $adjustedParameters["monitoringSamplingInSeconds"]
$cmdline_param_GMSA_ACCOUNT_NAME                  = $adjustedParameters["gmsaAccountName"]
$cmdline_param_SKIP_UPDATE_CHECK                  = $adjustedParameters["skipUpdateCheck"]
$cmdline_param_CERTIFICATE_FILE_PATH              = $adjustedParameters["certificateFilePath"]
$cmdline_param_CERTIFICATE_HOSTNAME               = $adjustedParameters["certificateHostname"]
$cmdline_param_CERTIFICATE_SECTION_LABEL          = $adjustedParameters["certificateSectionLabel"]

Initialize-OutputFormatLayout $cmdline_param_OUTPUT_FORMAT

# Started as early as possible so its background job's sampling period overlaps with the rest of
# report generation - see Start-CpuMemoryMonitoring in CpuMemoryInfo.ps1.
Start-CpuMemoryMonitoring $cmdline_param_MONITORING_PERIOD_MINUTES $cmdline_param_MONITORING_SAMPLING_SECONDS

Start-Winspect
