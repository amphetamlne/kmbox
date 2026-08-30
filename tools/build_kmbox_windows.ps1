# PIOKMbox Windows 一键编译脚本（默认 Waveshare RP2350-USB-A）
# 用法: pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build_kmbox_windows.ps1 [-Board <板名>] [-Mode <模式>]
# 可选板名: waveshare_rp2350_usb_a / muluoxing_rp2350_usb_a（见 boards/ 目录）
# 构建模式:
#   full        - 全量模式：清理所有构建中间产物后重新构建（默认）
#   incremental - 增量模式：仅清理编译输出，复用 CMake 配置和编译缓存
# 说明: 顶部变量按默认安装位置编写，路径不同请直接修改。
# 注意: 第三方依赖库及其下载缓存（_deps 中的源码包）始终保留，不会在清理中删除。
param(
    [string]$Board = 'waveshare_rp2350_usb_a',
    [ValidateSet('full', 'incremental')]
    [string]$Mode = 'full'
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

# ---- 构建前清理 ----
# 第三方依赖缓存（_deps 中的源码目录）始终保留，避免重复下载
$depSrcDirs = @('picotool-src')

if ($Mode -eq 'full') {
    Write-Output ">>> [全量模式] 清理构建中间产物..."
    if (Test-Path $buildDir) {
        # 收集需要保留的第三方依赖源码目录
        $preserved = @()
        $depsDir = Join-Path $buildDir '_deps'
        if (Test-Path $depsDir) {
            foreach ($d in $depSrcDirs) {
                $srcPath = Join-Path $depsDir $d
                if (Test-Path $srcPath) { $preserved += $srcPath }
            }
        }

        # 删除构建目录中的中间产物（保留 _deps 下的源码缓存）
        $itemsToClean = @(
            'CMakeCache.txt',
            'CMakeFiles',
            'build.ninja',
            'cmake_install.cmake',
            'compile_commands.json',
            '.ninja_deps',
            '.ninja_log',
            'generated',
            'pioasm',
            'pioasm-install',
            'lib',
            'pico-sdk',
            'pico_flash_region.ld',
            'rules.ninja'
        )
        # 编译输出文件
        $outputPatterns = @('PIOKMbox.bin', 'PIOKMbox.dis', 'PIOKMbox.elf',
                            'PIOKMbox.elf.map', 'PIOKMbox.hex', 'PIOKMbox.uf2')

        foreach ($item in $itemsToClean) {
            $path = Join-Path $buildDir $item
            if (Test-Path $path) {
                Remove-Item -Recurse -Force $path
                Write-Output "  已清理: $item"
            }
        }
        foreach ($pat in $outputPatterns) {
            $path = Join-Path $buildDir $pat
            if (Test-Path $path) {
                Remove-Item -Force $path
                Write-Output "  已清理: $pat"
            }
        }

        # 清理 _deps 中的构建产物（保留源码缓存）
        if (Test-Path $depsDir) {
            $depBuildDirs = Get-ChildItem -Path $depsDir -Directory |
                Where-Object { $_.Name -match '-build$|-subbuild$' }
            foreach ($dbDir in $depBuildDirs) {
                Remove-Item -Recurse -Force $dbDir.FullName
                Write-Output "  已清理: _deps/$($dbDir.Name)"
            }
        }
    }
    Write-Output ">>> [全量模式] 清理完成，将重新执行 CMake configure"
} else {
    Write-Output ">>> [增量模式] 仅清理编译输出文件..."
    if (Test-Path $buildDir) {
        $outputPatterns = @('PIOKMbox.bin', 'PIOKMbox.dis', 'PIOKMbox.elf',
                            'PIOKMbox.elf.map', 'PIOKMbox.hex', 'PIOKMbox.uf2')
        $cleaned = 0
        foreach ($pat in $outputPatterns) {
            $path = Join-Path $buildDir $pat
            if (Test-Path $path) {
                Remove-Item -Force $path
                Write-Output "  已清理: $pat"
                $cleaned++
            }
        }
        if ($cleaned -eq 0) { Write-Output "  无需清理" }
    }
    Write-Output ">>> [增量模式] 复用已有 CMake 配置和编译缓存"
}

$env:PICO_SDK_PATH = $sdk
$env:PICO_TOOLCHAIN_PATH = $toolchain
$env:HOME = $env:USERPROFILE

$cmakeCacheExists = Test-Path (Join-Path $buildDir 'CMakeCache.txt')
$needConfigure = ($Mode -eq 'full') -or (-not $cmakeCacheExists)

if ($needConfigure) {
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
} else {
    Write-Output ">>> [增量模式] CMakeCache.txt 存在，跳过 configure"
}

Write-Output ">>> CMake build..."
& cmake --build $buildDir -j ([Environment]::ProcessorCount)
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

$uf2 = Join-Path $buildDir 'PIOKMbox.uf2'
if (Test-Path $uf2) {
    Write-Output ">>> 编译成功: $uf2 ($((Get-Item $uf2).Length) bytes)"
} else {
    throw "未找到 PIOKMbox.uf2"
}
