$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = 'D:\Project\c++\kmbox'
Write-Output "--- 子模块检查 ---"
foreach ($sub in @('lib\Pico-PIO-USB','lib\kmbox-commands','lib\fast-protocol','lib\hid-defs','lib\led-utils','lib\peri-clock','lib\wire-protocol','lib\dma-uart')) {
    $f = Join-Path $root "$sub\CMakeLists.txt"
    if (Test-Path $f) { Write-Output "[OK]   $sub" } else { Write-Output "[MISS] $sub (无 CMakeLists.txt)" }
}
Write-Output "--- build-metro 现有产物 ---"
Get-ChildItem (Join-Path $root 'build-metro') -ErrorAction SilentlyContinue | Select-Object -First 10 | ForEach-Object { Write-Output $_.Name }
Write-Output "--- CMakeCache 关键项 ---"
$cache = Join-Path $root 'build-metro\CMakeCache.txt'
if (Test-Path $cache) { Select-String -Path $cache -Pattern 'PICO_BOARD:|CMAKE_BUILD_TYPE:|CMAKE_MAKE_PROGRAM|PICO_SDK_PATH' | ForEach-Object { Write-Output $_.Line } }
Write-Output "--- 可移动驱动器（BOOTSEL 检测） ---"
Get-Volume | Where-Object { $_.DriveType -eq 'Removable' } | ForEach-Object { Write-Output "$($_.DriveLetter): Label=$($_.FileSystemLabel) Size=$($_.Size)" }
