$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$root = 'D:\Project\c++\kmbox'
$buildDir = Join-Path $root 'build-metro'
$sdk = "$env:USERPROFILE\.pico-sdk\sdk\2.2.0-fresh"
$toolchain = "$env:USERPROFILE\.pico-sdk\toolchain"
$clionNinja = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\ninja\win\x64\ninja.exe'
$mingwBin = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw\bin'
$python = 'C:\Users\woan\Miniconda3\python.exe'
# 复用 bridge 构建时已安装的 picotool，避免重新联网下载
$picotoolDir = 'D:\Project\c++\kmbox\bridge\build-metro\_deps\picotool'

# 设置编译环境变量
$env:PICO_SDK_PATH = $sdk
$env:PICO_TOOLCHAIN_PATH = $toolchain
$env:PATH = "$mingwBin;$toolchain\bin;$env:PATH"
$env:HOME = $env:USERPROFILE
$env:CC = "$mingwBin\gcc.exe"
$env:CXX = "$mingwBin\g++.exe"

# 清理旧的错误缓存（保留 _deps 中的 picotool，如存在）
if (Test-Path $buildDir) {
    Write-Output ">>> 清理旧的 CMake 缓存..."
    Remove-Item -Recurse -Force (Join-Path $buildDir 'CMakeCache.txt') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $buildDir 'CMakeFiles') -ErrorAction SilentlyContinue
}

Write-Output ">>> CMake configure (KMBox main / waveshare_rp2350_usb_a)..."
& cmake -S $root -B $buildDir -G Ninja -DCMAKE_MAKE_PROGRAM="$clionNinja" -DPICO_BOARD=waveshare_rp2350_usb_a -DPICO_PLATFORM=rp2350-arm-s -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE="$python" -DPython3_FIND_STRATEGY=LOCATION -DPython3_FIND_REGISTRY=NEVER -Dpicotool_DIR="$picotoolDir"
if ($LASTEXITCODE -ne 0) { throw "CMake configure 失败" }

Write-Output ">>> CMake build..."
& cmake --build $buildDir -j ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

$uf2 = Join-Path $buildDir 'PIOKMbox.uf2'
if (Test-Path $uf2) {
    $size = (Get-Item $uf2).Length
    Write-Output ">>> 编译成功: $uf2 ($size bytes)"
} else {
    throw "未找到 PIOKMbox.uf2"
}
