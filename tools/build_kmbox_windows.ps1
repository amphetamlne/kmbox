# PIOKMbox Windows 一键编译脚本（默认 Waveshare RP2350-USB-A）
# 用法: pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build_kmbox_windows.ps1 [-Board <板名>]
# 可选板名: waveshare_rp2350_usb_a / muluoxing_rp2350_usb_a（见 boards/ 目录）
# 说明: 顶部变量按默认安装位置编写，路径不同请直接修改。
param(
    [string]$Board = 'waveshare_rp2350_usb_a'
)
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $root ('build-' + ($Board -replace '_rp2350_usb_a$', ''))
$sdk = "$env:USERPROFILE\.pico-sdk\sdk\2.2.0-fresh"
$toolchain = "$env:USERPROFILE\.pico-sdk\toolchain"
$python = (Get-Command python -ErrorAction SilentlyContinue).Source

# Ninja / 宿主编译器: 优先 PATH，其次 CLion 自带
$ninja = (Get-Command ninja -ErrorAction SilentlyContinue).Source
$clionBin = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin'
if (-not $ninja -and (Test-Path "$clionBin\ninja\win\x64\ninja.exe")) {
    $ninja = "$clionBin\ninja\win\x64\ninja.exe"
}
$mingwBin = "$clionBin\mingw\bin"
if (Test-Path $mingwBin) {
    $env:PATH = "$mingwBin;$toolchain\bin;$env:PATH"
    $env:CC = "$mingwBin\gcc.exe"
    $env:CXX = "$mingwBin\g++.exe"
}
if (-not $ninja) { throw "未找到 ninja，请安装或修改脚本中的路径" }

# 复用已有的 picotool（如存在），避免联网重新下载
$picotoolDir = Join-Path $root 'bridge\build-metro\_deps\picotool'

$env:PICO_SDK_PATH = $sdk
$env:PICO_TOOLCHAIN_PATH = $toolchain
$env:HOME = $env:USERPROFILE

Write-Output ">>> CMake configure (KMBox main / $Board)..."
$cmakeArgs = @(
    '-S', $root, '-B', $buildDir, '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DPICO_BOARD=$Board",
    '-DPICO_PLATFORM=rp2350-arm-s',
    '-DCMAKE_BUILD_TYPE=Release'
)
if ($python) {
    $cmakeArgs += @(
        "-DPython3_EXECUTABLE=$python",
        '-DPython3_FIND_STRATEGY=LOCATION',
        '-DPython3_FIND_REGISTRY=NEVER'
    )
}
if (Test-Path $picotoolDir) { $cmakeArgs += "-Dpicotool_DIR=$picotoolDir" }
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configure 失败" }

Write-Output ">>> CMake build..."
& cmake --build $buildDir -j ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

$uf2 = Join-Path $buildDir 'PIOKMbox.uf2'
if (Test-Path $uf2) {
    Write-Output ">>> 编译成功: $uf2 ($((Get-Item $uf2).Length) bytes)"
} else {
    throw "未找到 PIOKMbox.uf2"
}
