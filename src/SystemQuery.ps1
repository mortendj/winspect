function Get-MyWmiObject($className=$null, $query=$null) {
    Write-FunctionCallLog $PSBoundParameters
    if ($null -ne $className) {
        $wmiObject = Get-CimInstance -ClassName $className
    } elseif ($null -ne $query) {
        $wmiObject = Get-CimInstance -Query $query
    } else {
        $msg = "Parameter error retrieving WmiObject"
        Write-ErrorLog $msg
        throw $msg
    }
    Write-ReturnValue $wmiObject
}
