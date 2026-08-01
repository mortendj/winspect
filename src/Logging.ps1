$MAX_LOG_LINE_LENGTH = 300
$TRACE               = 0
$DEBUG               = 1
$INFO                = 2
$WARNING             = 3
$ERROR_LEVEL         = 4
$OFF                 = 9
$LOG_LEVEL           = @{
    "trace"   = $TRACE
    "debug"   = $DEBUG
    "info"    = $INFO
    "warning" = $WARNING
    "error"   = $ERROR_LEVEL
    "off"     = $OFF
}[$logLevel]

function Get-LogFilePath() {
    return $SCRIPT_PATH.Replace(".ps1", ".log")
}

function Remove-ExistingLogs() {
    if ($LOG_LEVEL -ne $OFF) {
        $logFilePath = Get-LogFilePath
        if (Test-Path -Path $logFilePath) {
            try {
                Invoke-WithRetry { Remove-Item -Path $logFilePath -Force -ErrorAction Stop } "Remove-Item"
            } catch {
                Remove-Item -Path $logFilePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Write-LogEntry($logLevel, $logLevelLabel, $message, $lineNumber) {
    if ($logLevel -ge $LOG_LEVEL) {
        $logEntry = "{0} {1} {2} ({3})" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $logLevelLabel, $message, $lineNumber
        $logFilePath = Get-LogFilePath
        try {
            Invoke-WithRetry { Add-Content -Path $logFilePath -Value $logEntry -ErrorAction Stop } "Add-Content"
        } catch {
            Add-Content -Path $logFilePath -Value $logEntry -ErrorAction SilentlyContinue
        }
    }
}

function Limit-TextString($textString) {
    $truncatedString = $textString -replace "`r?`n", "[LF]"
    if ($truncatedString.Length -gt $MAX_LOG_LINE_LENGTH) {
        $truncatedString = $truncatedString.Substring(0, $MAX_LOG_LINE_LENGTH - 3) + "..."
    }
    return $truncatedString
}

function Get-VariableDisplayValue($variable) {
    if ($null -eq $variable) {
        $displayValue = "NULL"
    } elseif ($variable -is [System.Object[]]) {
        $displayValue = "System.Object[$($variable.Length)]"
    } elseif ($variable -is [System.Array]) {
        $displayValue = "System.Array[$($variable.Length)]"
    } elseif ($variable -is [System.Collections.Hashtable]) {
        $displayValue = "System.Collections.Hashtable[$($variable.Count)]"
    } elseif ($variable -is [System.Management.Automation.PSCustomObject]) {
        $displayValue = Get-PSCustomObjectAsText $variable
        $displayValue = Limit-TextString $displayValue
    } elseif ($variable -is [System.Int32] -or
              $variable -is [System.Boolean] -or
              $variable -is [System.DateTime] -or
              $variable -is [System.Int64] -or
              $variable -is [System.UInt16] -or
              $variable -is [System.UInt32] -or
              $variable -is [System.Double] -or
              $variable -is [System.Management.Automation.ScriptBlock]) {
        $displayValue = $variable.ToString()
    } elseif ($variable -is [System.String]) {
        if ($variable -eq "") {
            $displayValue = "an empty string"
        } else {
            $displayValue = Limit-TextString $variable
        }
    } elseif ($variable -is [Microsoft.Management.Infrastructure.CimInstance]) {
        $displayValue = $variable.ToString()
    } else {
        $datatype = $variable.GetType().ToString()
        $displayValue = "The value is of type '$datatype'. Update function Get-VariableDisplayValue to also handle this data type."
    }
    return $displayValue
}

function Write-FunctionCallLog($parameters, $silently=$false) {
    $functionName = (Get-PSCallStack)[1].FunctionName
    $parameterValues = @()
    if ($silently -eq $true) {
        $parameterValues = "silent mode, parameter values not shown"
    } else {
        foreach ($parameter in $parameters.GetEnumerator()) {
            $parameterValues += Get-VariableDisplayValue $parameter.Value
        }
        $parameterValues = $parameterValues -join ", "
    }
    Write-LogEntry $DEBUG "DEBUG" "Function call: $($functionName)($parameterValues)" $($MyInvocation.ScriptLineNumber)
}

function Write-ReturnValue($returnValue) {
    $functionName = (Get-PSCallStack)[1].FunctionName
    $null = $displayValue = Get-VariableDisplayValue $returnValue
    Write-LogEntry $DEBUG "DEBUG" "Function output: '$functionName' returns '$displayValue'" $($MyInvocation.ScriptLineNumber)
    return ,$returnValue
}

function Write-VoidReturn() {
    $functionName = (Get-PSCallStack)[1].FunctionName
    Write-LogEntry $DEBUG "DEBUG" "Function termination: '$functionName'" $($MyInvocation.ScriptLineNumber)
}

function Write-TraceLog($message) {
    Write-LogEntry $TRACE "TRACE" $message $($MyInvocation.ScriptLineNumber)
}

function Write-DebugLog($message) {
    Write-LogEntry $DEBUG "DEBUG" $message $($MyInvocation.ScriptLineNumber)
}

function Write-InfoLog($message) {
    Write-LogEntry $INFO "INFO" $message $($MyInvocation.ScriptLineNumber)
}

function Write-WarningLog($message) {
    Write-LogEntry $WARNING "WARNING" $message $($MyInvocation.ScriptLineNumber)
}

function Write-ErrorLog($message, $exception=$null) {
    Write-LogEntry $ERROR_LEVEL "ERROR" $message $($MyInvocation.ScriptLineNumber)
    if ($null -ne $exception) {
        Write-LogEntry $ERROR_LEVEL "STACKTRACE" $exception.InvocationInfo.PositionMessage
    }
}

function Get-ErrorOutput([String]$message) {
    Write-LogEntry $ERROR_LEVEL "ERROR" $message $($MyInvocation.ScriptLineNumber)
    if ($message.Contains($ERROR_PREFIX)) {
        return $message
    } else {
        return "$ERROR_PREFIX $message"
    }
}

function Exit-WithMessage($message, $isInfoLevel) {
    Write-FunctionCallLog $PSBoundParameters
    if ($isInfoLevel) {
        Write-LogEntry $INFO "INFO" $message $($MyInvocation.ScriptLineNumber)
    } else {
        if (-not $message.Contains($ERROR_PREFIX)) {
            $message = "$ERROR_PREFIX $message"
        }
        Write-LogEntry $ERROR_LEVEL "ERROR" $message $($MyInvocation.ScriptLineNumber)
    }
    Write-Host $message
    exit 1
}

function Exit-WithErrorMessage($message) {
    $isInfoLevel = $false
    Exit-WithMessage $message $isInfoLevel
}

function Exit-WithInfoMessage($message) {
    $isInfoLevel = $true
    Exit-WithMessage $message $isInfoLevel
}
