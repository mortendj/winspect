################## VERSION ##################

$SCRIPT_VERSION          = "1.1.0"
$VERSION_TIMESTAMP       = "2026-10-03"
$SCRIPT_NAME             = "Winspect"
$VERSION_STRING          = "$SCRIPT_NAME v. $SCRIPT_VERSION ($VERSION_TIMESTAMP)"

################## OUTPUT FORMAT AND DESTINATION ##################

$TEXT_STYLE              = "text"
$MARKDOWN_STYLE          = "markdown"
$HTML_STYLE              = "html"
$TERMINAL_OUTPUT         = "terminal"
$FILE_OUTPUT             = "file"
$BOTH_OUTPUT_DESTINATION = "both"
$TERMINAL_OUTPUTS        = @($TERMINAL_OUTPUT, $BOTH_OUTPUT_DESTINATION)
$FILE_OUTPUTS            = @($FILE_OUTPUT, $BOTH_OUTPUT_DESTINATION)
$OUTPUT_FILE_NAME        = "winspect-report"
$TEXT_EXTENSION          = "txt"
$MARKDOWN_EXTENSION      = "md"
$HTML_EXTENSION          = "html"

################## TEXT AND LAYOUT ##################

$LF                      = "`n"
$CR                      = "`r"
$BR                      = "<br/>"
$PHYSICAL_NEWLINE        = "$CR$LF"
$FIELD_LABEL_SEPARATOR   = ": "
$SECTION_ITEM_MARKER     = "============"
$NON_FIELD_CHARACTERS    = @("#", "-", "<")

################## GENERAL ##################

$ERROR_PREFIX            = "ERROR -->"

################## DISK PERFORMANCE (WinSAT output parsing) ##################

$DISK_SPEED_PATTERN      = '(\d+\.\d+)\s*MB/s'
$DISK_LATENCY_PATTERN    = '95(?:th)?\s+[Pp]ercentil[e]?\s+([\d.]+\s*ms)'

################## UPDATE CHECK ##################

$GITHUB_REPO             = "mortendj/winspect"
$GITHUB_RELEASES_API_URL = "https://api.github.com/repos/$GITHUB_REPO/releases/latest"
$GITHUB_RELEASES_URL     = "https://github.com/$GITHUB_REPO/releases/latest"

################## HOST IDENTITY (VM manufacturer/model signatures) ##################

$VM_SIGNATURES           = @(
    @{ Pattern = "VMware"; Platform = "VMware" },
    @{ Pattern = "Virtual Machine"; Platform = "Hyper-V" },
    @{ Pattern = "VirtualBox"; Platform = "VirtualBox" },
    @{ Pattern = "KVM"; Platform = "KVM" },
    @{ Pattern = "QEMU"; Platform = "QEMU" },
    @{ Pattern = "Xen"; Platform = "Xen" }
)
