# 从 USB 层枚举所有设备，查找 KMBox (VID 0x9981) 是否出现
Get-PnpDevice -Class USB -PresentOnly | ForEach-Object {
    $dev = $_
    $inst = $dev.InstanceId
    if ($inst -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
        [PSCustomObject]@{
            Vid = $Matches[1]
            Pid = $Matches[2]
            Status = $dev.Status
            FriendlyName = $dev.FriendlyName
            InstanceId = $inst
        }
    }
} | Format-Table -AutoSize -Wrap
