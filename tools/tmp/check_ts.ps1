# 检查关键文件时间戳，判断 uf2 是否包含最新修改
$root = "D:\Project\c++\kmbox"
foreach ($f in @("build-metro\PIOKMbox.uf2", "usb_hid.c", "rawhid_control.c", "tusb_config.h")) {
    $i = Get-Item (Join-Path $root $f)
    Write-Output ("{0,-30} {1:yyyy-MM-dd HH:mm:ss} {2}" -f $f, $i.LastWriteTime, $i.Length)
}
