# 查系统日志中与该 HID 设备相关的错误事件
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$since = (Get-Date).AddHours(-2)
Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.Message -match '9981|4002|hidusb') -or
        ((($_.ProviderName -match 'hidusb|Kernel-PnP|USB') -or ($_.Id -in 400,410,411,420,430)) -and $_.Level -le 3)
    } |
    Select-Object -First 30 TimeCreated, Id, ProviderName, LevelDisplayName, Message |
    Format-List
