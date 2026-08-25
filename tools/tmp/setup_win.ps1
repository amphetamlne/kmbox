$ErrorActionPreference = "Continue"

Write-Host "========================================="
Write-Host "  PIOKMbox Build Environment Setup"
Write-Host "========================================="
Write-Host ""

$TOOLCHAIN_DIR = "$env:USERPROFILE\.pico-sdk\toolchain"
$PICO_SDK_DIR = "$env:USERPROFILE\.pico-sdk\sdk\2.2.0-fresh"
$PROJECT_DIR = "D:\Project\c++\kmbox"

# Step 1: Verify cmake
Write-Host "[1/5] Verifying cmake..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$cmakeVer = & cmake --version 2>$null | Select-Object -First 1
if ($cmakeVer) {
    Write-Host "  $cmakeVer"
} else {
    Write-Host "  ERROR: cmake not found. Exiting."
    exit 1
}
Write-Host ""

# Step 2: Install ARM toolchain
Write-Host "[2/5] Installing ARM GNU Toolchain 14.2..."
$gccCmd = Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
if ($gccCmd) {
    Write-Host "  Already installed: $($gccCmd.Source)"
} else {
    $toolchainUrl = "https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-mingw-w64-i686-arm-none-eabi.zip"
    $zipFile = "$env:TEMP\arm-toolchain.zip"

    if (!(Test-Path $TOOLCHAIN_DIR)) { New-Item -ItemType Directory -Path $TOOLCHAIN_DIR -Force | Out-Null }

    if (!(Test-Path $zipFile)) {
        Write-Host "  Downloading (~900MB, please wait)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $toolchainUrl -OutFile $zipFile -UseBasicParsing
        $ProgressPreference = 'Continue'
    }

    Write-Host "  Extracting..."
    Expand-Archive -Path $zipFile -DestinationPath $TOOLCHAIN_DIR -Force

    $binDir = Get-ChildItem -Path $TOOLCHAIN_DIR -Filter "arm-none-eabi-gcc.exe" -Recurse | Select-Object -First 1 -ExpandProperty DirectoryName
    if ($binDir) {
        $env:Path = "$binDir;$env:Path"
        $currentPath = [System.Environment]::GetEnvironmentVariable("Path","User")
        if ($currentPath -notlike "*$binDir*") {
            [System.Environment]::SetEnvironmentVariable("Path","$binDir;$currentPath","User")
        }
        Write-Host "  Installed: $binDir"
        & arm-none-eabi-gcc --version | Select-Object -First 1
    } else {
        Write-Host "  ERROR: arm-none-eabi-gcc.exe not found after extraction"
        exit 1
    }
}
Write-Host ""

# Step 3: Clone Pico SDK
Write-Host "[3/5] Installing Pico SDK 2.2.0..."
$initFile = Join-Path $PICO_SDK_DIR "pico_sdk_init.cmake"
if (Test-Path $initFile) {
    Write-Host "  Pico SDK already exists, skipping"
} else {
    Write-Host "  Cloning Pico SDK (may take a few minutes)..."
    $parentDir = Split-Path $PICO_SDK_DIR -Parent
    if (!(Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
    if (Test-Path $PICO_SDK_DIR) { Remove-Item $PICO_SDK_DIR -Recurse -Force }

    & git clone --branch 2.2.0 --depth 1 https://github.com/raspberrypi/pico-sdk.git $PICO_SDK_DIR
    Push-Location $PICO_SDK_DIR
    & git submodule update --init --recursive --depth 1
    Pop-Location
    Write-Host "  Pico SDK installed"
}
$env:PICO_SDK_PATH = $PICO_SDK_DIR
Write-Host "  PICO_SDK_PATH=$PICO_SDK_DIR"
Write-Host ""

# Step 4: Init submodules
Write-Host "[4/5] Initializing project git submodules..."
Push-Location $PROJECT_DIR
& git submodule update --init --recursive
Pop-Location
Write-Host "  Submodules initialized"
Write-Host ""

# Step 5: Build
Write-Host "[5/5] Building firmware (metro)..."
$buildDir = Join-Path $PROJECT_DIR "build-metro"
if (!(Test-Path $buildDir)) { New-Item -ItemType Directory -Path $buildDir -Force | Out-Null }

Push-Location $buildDir
$env:PICO_SDK_PATH = $PICO_SDK_DIR

# Find a build generator
$ninja = Get-Command ninja -ErrorAction SilentlyContinue
$generator = "Ninja"
if (!$ninja) {
    $nmake = Get-Command nmake -ErrorAction SilentlyContinue
    if ($nmake) {
        $generator = "NMake Makefiles"
    } else {
        $make = Get-Command make -ErrorAction SilentlyContinue
        if ($make) {
            $generator = "MinGW Makefiles"
        } else {
            Write-Host "  Installing Ninja build tool..."
            & winget install --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements --silent
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            $generator = "Ninja"
        }
    }
}

Write-Host "  CMake Generator: $generator"
& cmake $PROJECT_DIR -DPICO_BOARD=adafruit_metro_rp2350 -DPICO_PLATFORM=rp2350-arm-s -DCMAKE_BUILD_TYPE=Release -G $generator

if ($LASTEXITCODE -ne 0) {
    Write-Host "  CMake configure FAILED!"
    Pop-Location
    exit 1
}

& cmake --build . --config Release

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Build FAILED!"
    Pop-Location
    exit 1
}

Pop-Location
Write-Host ""

# Result
Write-Host "========================================="
Write-Host "  BUILD COMPLETE!"
Write-Host "========================================="
$uf2 = Join-Path $buildDir "PIOKMbox.uf2"
if (Test-Path $uf2) {
    $size = (Get-Item $uf2).Length
    Write-Host "  Firmware: $uf2 ($size bytes)"
} else {
    Write-Host "  Firmware not found in output directory"
}
