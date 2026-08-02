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

.PARAMETER parametersFile
Path to a file with parameter name/value pairs (one per line) that act as defaults. Empty lines and
lines starting with '#' are ignored. Command line parameters still take precedence over anything
set in this file.

.PARAMETER gmsaAccountName
Name of a Group Managed Service Account to check. When supplied, reports whether the account
exists in Active Directory and whether this host can use it. Requires this host to be
domain-joined and have the ActiveDirectory module installed; otherwise reports why it can't check.
Omitted by default, in which case this section doesn't appear at all.

.PARAMETER skipUpdateCheck
Skips checking GitHub for a newer release. The check fails silently anyway (e.g. on hosts with no
outbound internet access), so this is only useful to avoid the network call/delay entirely.

.PARAMETER certificateFilePath
Path to a certificate file to check the expiration of, in addition to the local machine store scan
- useful for certificates an application manages itself as a file rather than through Windows'
certificate store. Takes precedence over -certificateHostname if both are supplied.

.PARAMETER certificateHostname
A hostname (optionally hostname:port, default port 443) to fetch a live TLS certificate from and
check its expiration, in addition to the local machine store scan.

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
   [string]$certificateHostname = ""
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
$cmdline_param_GMSA_ACCOUNT_NAME                  = $adjustedParameters["gmsaAccountName"]
$cmdline_param_SKIP_UPDATE_CHECK                  = $adjustedParameters["skipUpdateCheck"]
$cmdline_param_CERTIFICATE_FILE_PATH              = $adjustedParameters["certificateFilePath"]
$cmdline_param_CERTIFICATE_HOSTNAME               = $adjustedParameters["certificateHostname"]

Initialize-OutputFormatLayout $cmdline_param_OUTPUT_FORMAT

Start-Winspect
