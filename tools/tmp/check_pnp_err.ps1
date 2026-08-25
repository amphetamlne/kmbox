# 查询所有有问题的 PnP 设备（ConfigManagerErrorCode > 0）
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    Select-Object Name, DeviceID, ConfigManagerErrorCode, Status |
    Format-List
