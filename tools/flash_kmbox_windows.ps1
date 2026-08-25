# PIOKMbox BOOTSEL 轮询烧录脚本
# 用法: 运行脚本后，按住板上 BOOTSEL 再按一下 RESET（或按住 BOOTSEL 插入 USB 线）
#       脚本检测到 BOOTSEL 盘后自动复制 uf2 并等待烧录完成。
# 用法: pwsh -NoProfile -ExecutionPolicy Bypass -File tools/flash_kmbox_windows.ps1
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Split-Path -Parent $PSScriptRoot

# 按优先级查找固件产物
$candidates = @(
    (Join-Path $root 'build-waveshare\PIOKMbox.uf2'),
    (Join-Path $root 'build-metro\PIOKMbox.uf2')
)
$uf2 = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $uf2) { throw "未找到 PIOKMbox.uf2，请先运行 tools/build_kmbox_windows.ps1 编译" }
Write-Output ">>> 固件: $uf2"

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
