$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$uf2 = 'D:\Project\c++\kmbox\bridge\build-metro\kmbox_bridge.uf2'
$dest = 'E:\'

Write-Output ">>> 复制固件到 E: (RPI-RP2/RP2350)..."
try {
    Copy-Item -Path $uf2 -Destination $dest -Force
    Write-Output ">>> 复制命令已返回"
} catch {
    # 板子在接收完固件后会立即重启并断开 USB，可能抛出 IO 错误，属正常现象
    Write-Output ">>> 复制过程中设备断开（常见于烧录完成瞬间）: $($_.Exception.Message)"
}

Start-Sleep -Seconds 4
$vol = Get-Volume | Where-Object { $_.DriveLetter -eq 'E' }
if ($vol) {
    Write-Output ">>> E: 仍然存在（Label=$($vol.FileSystemLabel)），板子可能未进入运行态或烧录未完成"
} else {
    Write-Output ">>> E: 盘已消失 —— 烧录成功，板子已重启运行新固件"
}
