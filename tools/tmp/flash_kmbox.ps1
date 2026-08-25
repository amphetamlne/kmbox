$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$uf2 = 'D:\Project\c++\kmbox\build-metro\PIOKMbox.uf2'

Write-Output ">>> 等待 BOOTSEL 盘出现（请按住 BOOTSEL 后按一下 Reset）..."
$drive = $null
for ($i = 0; $i -lt 90; $i++) {
    $drive = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -First 1
    if ($drive) { break }
    Start-Sleep -Seconds 2
}
if (-not $drive) { throw "等待超时（180秒），未检测到 BOOTSEL 盘" }

$dest = "$($drive.DriveLetter):\"
Write-Output ">>> 检测到 $($drive.DriveLetter): (Label=$($drive.FileSystemLabel))，开始烧录..."
try {
    Copy-Item -Path $uf2 -Destination $dest -Force
    Write-Output ">>> 复制命令已返回"
} catch {
    Write-Output ">>> 复制过程中设备断开（烧录完成瞬间的常见现象）: $($_.Exception.Message)"
}

Start-Sleep -Seconds 5
$still = Get-Volume | Where-Object { $_.DriveLetter -eq $drive.DriveLetter }
if ($still) {
    Write-Output ">>> 警告: $($drive.DriveLetter): 仍然存在，烧录可能未完成"
} else {
    Write-Output ">>> 烧录完成，板子已重启"
}
