# 在 uf2/elf 里搜索 desc_rawhid_control 字节特征，确认固件含控制接口描述符
$path = "D:\Project\c++\kmbox\build-metro\PIOKMbox.uf2"
$b = [System.IO.File]::ReadAllBytes($path)
Write-Output ("uf2 size: " + $b.Length)
$pat = [byte[]](0x06, 0xC0, 0xFF, 0x0A, 0x00, 0x0C, 0xA1, 0x01)
$found = -1
for ($k = 0; $k -lt $b.Length - 8; $k++) {
    $ok = $true
    for ($j = 0; $j -lt 8; $j++) {
        if ($b[$k + $j] -ne $pat[$j]) { $ok = $false; break }
    }
    if ($ok) { $found = $k; break }
}
Write-Output ("desc_rawhid_control pattern at offset: " + $found)
