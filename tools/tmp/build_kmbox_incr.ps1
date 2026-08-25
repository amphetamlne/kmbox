$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$root = 'D:\Project\c++\kmbox'
$buildDir = Join-Path $root 'build-metro'
$sdk = "$env:USERPROFILE\.pico-sdk\sdk\2.2.0-fresh"
$toolchain = "$env:USERPROFILE\.pico-sdk\toolchain"
$clionNinja = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\ninja\win\x64\ninja.exe'
$mingwBin = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw\bin'
$python = 'C:\Users\woan\Miniconda3\python.exe'
$picotoolDir = 'D:\Project\c++\kmbox\bridge\build-metro\_deps\picotool'

$env:PICO_SDK_PATH = $sdk
$env:PICO_TOOLCHAIN_PATH = $toolchain
$env:PATH = "$mingwBin;$toolchain\bin;$env:PATH"
$env:HOME = $env:USERPROFILE

# 增量构建（不清缓存）；缓存缺失时自动 configure
if (-not (Test-Path (Join-Path $buildDir 'CMakeCache.txt'))) {
    Write-Output '>>> CMake configure...'
    & cmake -S $root -B $buildDir -G Ninja -DCMAKE_MAKE_PROGRAM="$clionNinja" -DPICO_BOARD=waveshare_rp2350_usb_a -DPICO_PLATFORM=rp2350-arm-s -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE="$python" -DPython3_FIND_STRATEGY=LOCATION -DPython3_FIND_REGISTRY=NEVER -Dpicotool_DIR="$picotoolDir"
    if ($LASTEXITCODE -ne 0) { throw 'CMake configure 失败' }
}

Write-Output '>>> CMake incremental build...'
& cmake --build $buildDir -j ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) { throw '编译失败' }

$uf2 = Join-Path $buildDir 'PIOKMbox.uf2'
if (Test-Path $uf2) {
    $size = (Get-Item $uf2).Length
    Write-Output ">>> 编译成功: $uf2 ($size bytes)"
} else {
    throw '未找到 PIOKMbox.uf2'
}
