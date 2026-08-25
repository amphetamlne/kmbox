$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '9981|PIOKM|Hurricane' } |
    Select-Object FriendlyName, Status, InstanceId | Format-List
Write-Output '--- 端口(COM) ---'
Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status | Format-Table -AutoSize
