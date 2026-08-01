$winsatMeasurements = @{}

function Get-Disks() {
    Write-FunctionCallLog $PSBoundParameters
    $logicalDisks = Get-MyWmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    Write-ReturnValue @($logicalDisks)
}

function Get-DiskCapacity() {
    Write-FunctionCallLog $PSBoundParameters
    $all_disks = @()
    $disks = Get-Disks
    foreach ($disk in $disks) {
        $driveLetter = $($disk.DeviceID)
        $freeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
        $totalSpace = [math]::Round($disk.Size / 1GB, 2)
        $usedSpace = $totalSpace - $freeSpace
        $usedSpaceText = Format-InvariantNumber $usedSpace "N1"
        $totalSpaceText = Format-InvariantNumber $totalSpace "N1"
        $all_disks += "$INDENTATION$driveLetter -> $usedSpaceText GB / $totalSpaceText GB"
    }
    Write-ReturnValue "$($all_disks -join $LOGICAL_NEWLINE)"
}

function Invoke-WinSATCommand($driveLetter, $pattern) {
    Write-FunctionCallLog $PSBoundParameters
    if (-not $winsatMeasurements.ContainsKey($driveLetter)) {
        Write-DebugLog "Running winsat for drive $driveLetter"
        try {
            $winsatMeasurements[$driveLetter] = Invoke-ExternalCommand "winsat" @("disk", "-drive", $driveLetter)
        } catch {
            $msg = "Unable to obtain disk performance numbers using winsat tool for drive $($driveLetter): $($_.Exception.Message)"
            Write-ErrorLog $msg $_
            throw $msg
        }
    } else {
        Write-DebugLog "Using existing winsat measurements for drive $driveLetter"
    }
    $matches = [regex]::Matches($winsatMeasurements[$driveLetter], $pattern)
    $results = @()
    foreach ($match in $matches) {
        $results += $match.Groups[1].Value
    }
    Write-ReturnValue $results
}

function Measure-DiskSpeed($driveLetter) {
    $speeds = Invoke-WinSATCommand $driveLetter $DISK_SPEED_PATTERN
    if ($speeds.Length -ne 3) {
        $msg = "Failed to scrape disk performance data from winsat output"
        Write-ErrorLog $msg
        throw $msg
    }
    Write-ReturnValue $speeds
}

function Measure-DiskLatency($driveLetter) {
    $latencies = Invoke-WinSATCommand $driveLetter $DISK_LATENCY_PATTERN
    if ($latencies.Length -eq 0) {
        $msg = "Failed to scrape latency data from winsat output"
        Write-ErrorLog $msg
        throw $msg
    }
    Write-ReturnValue $latencies
}

function Get-DiskSpeedUsingMeasureCommand($driveLetter) {
    Write-FunctionCallLog $PSBoundParameters
    $testFilePath = "$($driveLetter)\xyz_testfile_xyz.tmp"
    $fileSizeMB = 1000
    $bufferSize = 64KB

    try {
        $writeSpeed = Measure-Command {
            $randomContent = New-Object byte[] ($fileSizeMB * 1MB)
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($randomContent)
            $fileStream = [System.IO.File]::Create($testFilePath)
            $fileStream.Write($randomContent, 0, $randomContent.Length)
            $fileStream.Close()
        }
    } catch {
        $errorMsg = "Failed to create or write to the file at path '$testFilePath': $($_.Exception.Message)"
        Write-ErrorLog $errorMsg $_
        throw $errorMsg
    }

    try {
        $readSpeed = Measure-Command {
            $fileStream = [System.IO.File]::OpenRead($testFilePath)
            $buffer = New-Object byte[] $bufferSize
            while ($fileStream.Read($buffer, 0, $buffer.Length) -ne 0) { }
            $fileStream.Close()
        }
    } catch {
        $errorMsg = "Failed to read the file at path '$testFilePath': $($_.Exception.Message)"
        Write-ErrorLog $errorMsg $_
        throw $errorMsg
    }

    try {
        Remove-Item $testFilePath -ErrorAction Stop
    } catch {
        $errorMsg = "Failed to remove the file at path '$testFilePath': $($_.Exception.Message)"
        Write-ErrorLog $errorMsg $_
        throw $errorMsg
    }

    $writeSpeedMBs = Format-InvariantNumber ([math]::Round($fileSizeMB / $writeSpeed.TotalSeconds, 2)) "N2"
    $readSpeedMBs = Format-InvariantNumber ([math]::Round($fileSizeMB / $readSpeed.TotalSeconds, 2)) "N2"
    Write-ReturnValue @($writeSpeedMBs, $readSpeedMBs)
}

function Get-DiskSpeed() {
    Write-FunctionCallLog $PSBoundParameters
    $all_disks = @()
    $disks = Get-Disks
    foreach ($disk in $disks) {
        $driveLetter = $($disk.DeviceID)
        if ($cmdline_param_SKIP_DISK_PERFOR_MEASURE) {
            $speedReport = "disk performance testing skipped due to -skipDiskPerformanceMeasurements parameter"
        } else {
            try {
                $winsatSpeeds = Measure-DiskSpeed $driveLetter
            } catch {
                Write-DebugLog "Failed to obtain data from winsat: $_"
                $winsatSpeeds = @('-','-','-')
            }
            try {
                $measureCmdSpeeds = Get-DiskSpeedUsingMeasureCommand $driveLetter
            } catch {
                Write-DebugLog "Failed to obtain data from measure command: $_"
                $measureCmdSpeeds = @('-','-')
            }
            $speeds = $winsatSpeeds + $measureCmdSpeeds
            Write-DebugLog "Concatinated speed data: $speeds"
            $speedReport = "$($speeds[0]) (RR), $($speeds[1]) (RS), $($speeds[2]) (WS), $($speeds[3]) (WF), $($speeds[4]) (RF)"
        }
        $all_disks += "$INDENTATION$driveLetter -> $speedReport"
    }
    Write-ReturnValue "$($all_disks -join $LOGICAL_NEWLINE)"
}

function Get-DiskLatency() {
    Write-FunctionCallLog $PSBoundParameters
    $all_disks = @()
    $disks = Get-Disks
    foreach ($disk in $disks) {
        $driveLetter = $($disk.DeviceID)
        if ($cmdline_param_SKIP_DISK_PERFOR_MEASURE) {
            $latencyReport = "disk performance testing skipped due to -skipDiskPerformanceMeasurements parameter"
        } else {
            try {
                $winsatLatency = Measure-DiskLatency $driveLetter
            } catch {
                Write-DebugLog "Failed to obtain data from winsat: $_"
                $winsatLatency = @('-')
            }
            $latencyReport = $winsatLatency
        }
        $all_disks += "$INDENTATION$driveLetter -> $latencyReport"
    }
    Write-ReturnValue "$($all_disks -join $LOGICAL_NEWLINE)"
}
