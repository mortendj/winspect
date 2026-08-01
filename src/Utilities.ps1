function Get-LocalTime() {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

function Get-UserWithDomain() {
    Write-FunctionCallLog $PSBoundParameters
    $userDomain = [System.Environment]::UserDomainName
    $userName = [System.Environment]::UserName
    Write-ReturnValue "$userDomain\$userName"
}

function Invoke-ExternalCommand($commandName, $commandArgs) {
    Write-FunctionCallLog $PSBoundParameters
    $tempDir = [System.IO.Path]::GetTempPath()
    $stdOutFile = Join-Path $tempDir "$([guid]::NewGuid()).out"
    $stdErrFile = Join-Path $tempDir "$([guid]::NewGuid()).err"
    try {
        Start-Process -FilePath $commandName -ArgumentList $commandArgs -NoNewWindow -Wait `
            -RedirectStandardOutput $stdOutFile -RedirectStandardError $stdErrFile
        $standardOutput = Get-Content -Path $stdOutFile -ErrorAction SilentlyContinue
        $errorOutput = Get-Content -Path $stdErrFile -ErrorAction SilentlyContinue
    } catch {
        Write-ErrorLog "Command '$commandName $commandArgs' failed: $($_.Exception.Message)" $_
        throw
    } finally {
        Remove-Item $stdOutFile, $stdErrFile -ErrorAction SilentlyContinue
    }
    if ($errorOutput) {
        Write-ErrorLog $errorOutput
        throw $errorOutput
    }
    Write-ReturnValue $standardOutput
}

function Invoke-WithRetry([ScriptBlock]$command, $functionName, $maxRetries=3, $retryDelay=1) {
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            & $command
            break
        } catch {
            Update-FileWriteErrorCount "$functionName --> $_"
            if ($attempt -ge $maxRetries) {
                throw "Failed to execute command '$command' after $maxRetries attempts"
            }
            Start-Sleep -Seconds $retryDelay
        }
    }
}

function Update-FileWriteErrorCount($ErrorType) {
    if (-not $script:FileWriteErrorCounts) {
        $script:FileWriteErrorCounts = @{}
    }
    if ($script:FileWriteErrorCounts.ContainsKey($ErrorType)) {
        $script:FileWriteErrorCounts[$ErrorType]++
    } else {
        $script:FileWriteErrorCounts[$ErrorType] = 1
    }
}

function Format-InvariantNumber($value, $formatString = $null) {
    if ($null -ne $formatString) {
        return $value.ToString($formatString, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}
