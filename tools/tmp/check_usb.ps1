$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output '--- USB 控制器下设备 ---'
Get-PnpDevice -PresentOnly -Class USB -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status, InstanceId | Format-Table -AutoSize -Wrap
Write-Output '--- HIDClass 设备 ---'
Get-PnpDevice -PresentOnly -Class HIDClass -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status, InstanceId | Format-Table -AutoSize -Wrap
