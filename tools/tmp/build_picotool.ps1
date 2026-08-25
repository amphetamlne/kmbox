$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$sdk = "$env:USERPROFILE\.pico-sdk\sdk\2.2.0-fresh"
$src = 'D:\Project\c++\kmbox\bridge\build-metro\_deps\picotool-src'
$buildDir = 'D:\Project\c++\kmbox\bridge\build-metro\_deps\picotool-build'
$installDir = 'D:\Project\c++\kmbox\bridge\build-metro\_deps'
$clionNinja = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\ninja\win\x64\ninja.exe'
$mingwBin = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw\bin'

$env:PATH = "$mingwBin;$env:PATH"
$env:CC = "$mingwBin\gcc.exe"
$env:CXX = "$mingwBin\g++.exe"

Write-Output ">>> checkout 2.2.0..."
git -C $src checkout 2.2.0 2>&1 | ForEach-Object { Write-Output $_ }

Write-Output ">>> configure picotool..."
& cmake -S $src -B $buildDir -G Ninja -DCMAKE_MAKE_PROGRAM="$clionNinja" -DPICO_SDK_PATH="$sdk" -DPICOTOOL_NO_LIBUSB=1 -DPICOTOOL_FLAT_INSTALL=1 -DCMAKE_INSTALL_PREFIX="$installDir" -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { throw "picotool configure 失败" }

Write-Output ">>> build picotool..."
& cmake --build $buildDir -j ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) { throw "picotool 编译失败" }

Write-Output ">>> install picotool..."
& cmake --install $buildDir
if ($LASTEXITCODE -ne 0) { throw "picotool 安装失败" }

$exe = Join-Path $installDir 'picotool\picotool.exe'
if (Test-Path $exe) {
    Write-Output ">>> picotool 就绪: $exe"
    & $exe version
} else {
    throw "未找到 $exe"
}
