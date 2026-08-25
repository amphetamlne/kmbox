$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output "--- SDK TinyUSB 子模块 ---"
$tusb = 'C:\Users\woan\.pico-sdk\sdk\2.2.0-fresh\lib\tinyusb\src\tusb.h'
if (Test-Path $tusb) { Write-Output "[OK] tinyusb 已初始化" } else { Write-Output "[MISS] tinyusb 未初始化" }
Write-Output "--- MSVC 主机编译器 ---"
foreach ($p in @('C:\Program Files\Microsoft Visual Studio\2022','C:\Program Files (x86)\Microsoft Visual Studio\2022','C:\Program Files (x86)\Microsoft Visual Studio\2019','C:\BuildTools')) {
    if (Test-Path $p) {
        Write-Output "[EXISTS] $p"
        Get-ChildItem -Path $p -Recurse -Filter 'cl.exe' -ErrorAction SilentlyContinue | Select-Object -First 2 | ForEach-Object { Write-Output "         cl.exe -> $($_.FullName)" }
    }
}
foreach ($c in @('cl','gcc','clang')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { Write-Output "[OK] $c -> $($cmd.Source)" } else { Write-Output "[MISS] $c" }
}
Write-Output "--- VS Installer 产品 ---"
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) { & $vswhere -latest -property installationPath } else { Write-Output "(无 vswhere)" }
