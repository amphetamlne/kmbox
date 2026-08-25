$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$root = 'D:\Project\c++\kmbox'
$buildDir = Join-Path $root 'bridge\build-metro'
$sdk = "$env:USERPROFILE\.pico-sdk\sdk\2.2.0-fresh"
$toolchain = "$env:USERPROFILE\.pico-sdk\toolchain"
$make = 'C:\Program Files (x86)\GnuWin32\bin\make.exe'
$clionNinja = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\ninja\win\x64\ninja.exe'
$mingwBin = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw\bin'

# 设置编译环境变量
$env:PICO_SDK_PATH = $sdk
$env:PICO_TOOLCHAIN_PATH = $toolchain
# 宿主工具（picotool/pioasm）用 CLion 自带 MinGW；交叉编译由 PICO_TOOLCHAIN_PATH 决定
$env:PATH = "$mingwBin;$toolchain\bin;$env:PATH"
$env:HOME = $env:USERPROFILE
$env:CC = "$mingwBin\gcc.exe"
$env:CXX = "$mingwBin\g++.exe"

# 清理旧的 CMake 缓存（保留 _deps 中的 picotool）
if (Test-Path $buildDir) {
    Write-Output ">>> 清理旧的 CMake 缓存..."
    Remove-Item -Recurse -Force (Join-Path $buildDir 'CMakeCache.txt') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $buildDir 'CMakeFiles') -ErrorAction SilentlyContinue
}

$python = 'C:\Users\woan\Miniconda3\python.exe'

Write-Output ">>> CMake configure (bridge metro)..."
& cmake -S "$root\bridge" -B $buildDir -G Ninja -DCMAKE_MAKE_PROGRAM="$clionNinja" -DPICO_BOARD=adafruit_metro_rp2350 -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE="$python" -DPython3_FIND_STRATEGY=LOCATION -DPython3_FIND_REGISTRY=NEVER
if ($LASTEXITCODE -ne 0) { throw "CMake configure 失败" }

Write-Output ">>> CMake build..."
& cmake --build $buildDir -j ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

$uf2 = Join-Path $buildDir 'kmbox_bridge.uf2'
if (Test-Path $uf2) {
    $size = (Get-Item $uf2).Length
    Write-Output ">>> 编译成功: $uf2 ($size bytes)"
} else {
    throw "未找到 kmbox_bridge.uf2"
}
