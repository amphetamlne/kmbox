$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Start-Sleep -Seconds 3
Write-Output "=== USB 设备（查找 KMBox/Hurricane/RP2350） ==="
Get-PnpDevice -Class 'Ports' -Status OK -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ("[PORT] " + $_.FriendlyName) }
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'KMBox|Hurricane|RP2350|CDC|Serial' } |
    Select-Object -First 10 |
    ForEach-Object { Write-Output ("[USB] " + $_.Class + " - " + $_.FriendlyName) }
Write-Output "=== COM 端口 ==="
[System.IO.Ports.SerialPort]::GetPortNames() | ForEach-Object { Write-Output $_ }
