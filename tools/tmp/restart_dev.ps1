# 重启 MI_01 设备节点并重查状态
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$devs = Get-PnpDevice | Where-Object { $_.InstanceId -like 'USB\VID_9981&PID_4002*' }
foreach ($d in $devs) {
    Write-Output ("before: {0} -> {1}" -f $d.InstanceId, $d.Status)
}
$target = $devs | Where-Object { $_.InstanceId -like '*MI_01*' } | Select-Object -First 1
if ($target) {
    Write-Output ("restarting: {0}" -f $target.InstanceId)
    pnputil /restart-device $target.InstanceId
    Start-Sleep -Seconds 3
}
$devs2 = Get-PnpDevice | Where-Object { $_.InstanceId -like 'USB\VID_9981&PID_4002*' }
foreach ($d in $devs2) {
    Write-Output ("after: {0} -> {1}" -f $d.InstanceId, $d.Status)
}
