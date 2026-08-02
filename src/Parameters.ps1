function Get-ParametersFromFile {
    [CmdletBinding()]
    param($parametersFilePath)
    Write-FunctionCallLog $PSBoundParameters
    $parameters = @{}
    Get-Content -Path $parametersFilePath | ForEach-Object {
        $_ = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($_) -or $_.StartsWith('#')) {
            return
        }
        $lineWithoutComments = $_ -split '#', 2
        $lineWithoutComments = $lineWithoutComments[0].Trim()
        $parts = $lineWithoutComments -split '\s+', 2
        if ($parts.Length -eq 2) {
            $key = $parts[0]
            $value = $parts[1]
            if ($value -match '^\$?true$' -or $value -match '^\$?false$') {
                $value = [bool]::Parse($value.Trim('$').ToLower())
            } elseif ($value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Trim('"')
            }
            $parameters[$key] = $value
        } else {
            Write-Warning "Skipping invalid line: $_"
        }
    }
    Write-ReturnValue $parameters
}

function Get-CmdLineParameterValues() {
    return $PSCmdlet.MyInvocation.BoundParameters
}

function Get-AllParameterValues {
    Write-FunctionCallLog $PSBoundParameters
    $excludedParameters = @(
        "Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction",
        "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable",
        "OutBuffer", "PipelineVariable", "ProgressAction"
    )
    $output = @{}
    $parameters = $PSCmdlet.MyInvocation.MyCommand.Parameters
    foreach ($param in $parameters.GetEnumerator()) {
        $paramName = $param.Key
        if ($excludedParameters -contains $paramName) {
            continue
        }
        if ($PSBoundParameters.ContainsKey($paramName)) {
            $paramValue = $PSBoundParameters[$paramName]
        } else {
            $paramValue = Get-Variable -Name $paramName -ValueOnly
        }
        $output[$paramName] = $paramValue
    }
    Write-ReturnValue $output
}

function Get-AdjustedParameters($parametersFilePath) {
    $adjustedParameters = @{}
    $parametersFromFile = $null
    if ($parametersFilePath -ne "") {
        if (-Not (Test-Path -Path $parametersFilePath)) {
            $msg = "File not found: $parametersFilePath"
            Write-ErrorLog $msg
            throw $msg
        }
        $parametersFromFile = Get-ParametersFromFile $parametersFilePath
    }
    $cmdLineParameters = Get-CmdLineParameterValues
    $allValidParameters = Get-AllParameterValues

    foreach ($param in $allValidParameters.Keys) {
        if ($cmdLineParameters.ContainsKey($param)) {
            $adjustedParameters[$param] = $cmdLineParameters[$param]
        } elseif (($null -ne $parametersFromFile) -and ($parametersFromFile.ContainsKey($param))) {
            $adjustedParameters[$param] = $parametersFromFile[$param]
        } else {
            $adjustedParameters[$param] = $allValidParameters[$param]
        }
    }
    return $adjustedParameters
}
