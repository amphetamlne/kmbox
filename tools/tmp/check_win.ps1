# Check Windows-side build tools
Write-Host "=== Checking Windows build tools ==="
Write-Host ""

# Check cmake
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmake) { Write-Host "cmake: $($cmake.Source)" } else { Write-Host "cmake: NOT FOUND" }

# Check arm-none-eabi-gcc
$gcc = Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
if ($gcc) { Write-Host "arm-none-eabi-gcc: $($gcc.Source)" } else { Write-Host "arm-none-eabi-gcc: NOT FOUND" }

# Check Pico SDK
$picoPath = "$env:USERPROFILE\.pico-sdk"
if (Test-Path $picoPath) { Write-Host "Pico SDK dir: $picoPath exists"; Get-ChildItem $picoPath -Recurse -Depth 2 | Select-Object FullName } else { Write-Host "Pico SDK: NOT FOUND at $picoPath" }

# Check common install locations
$paths = @(
    "C:\Program Files\CMake",
    "C:\Program Files\Microsoft Visual Studio",
    "C:\Program Files\GNU Arm Embedded Toolchain",
    "C:\Program Files (x86)\GNU Arm Embedded Toolchain",
    "C:\Program Files\Arm GNU Toolchain",
    "C:\Program Files (x86)\Arm GNU Toolchain"
)
Write-Host ""
Write-Host "=== Checking common install paths ==="
foreach ($p in $paths) {
    if (Test-Path $p) { Write-Host "FOUND: $p" }
}

# Check Visual Studio cl.exe
$vsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    Write-Host ""
    Write-Host "=== Visual Studio ==="
    & $vsWhere -latest -property installationPath
}
