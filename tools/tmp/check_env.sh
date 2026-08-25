#!/bin/bash
echo "=== Checking build environment ==="
echo ""

echo -n "arm-none-eabi-gcc: "
if which arm-none-eabi-gcc >/dev/null 2>&1; then
    arm-none-eabi-gcc --version | head -1
else
    echo "NOT FOUND"
fi

echo -n "cmake: "
if which cmake >/dev/null 2>&1; then
    cmake --version | head -1
else
    echo "NOT FOUND"
fi

echo ""
echo "PICO_SDK_PATH=${PICO_SDK_PATH:-NOT SET}"

echo ""
echo "Checking default Pico SDK locations..."
if [ -d "$HOME/.pico-sdk/sdk" ]; then
    ls -d "$HOME/.pico-sdk/sdk/"* 2>/dev/null
else
    echo "No ~/.pico-sdk/sdk directory found"
fi

echo ""
echo "Checking git submodules..."
cd /mnt/d/Project/c++/kmbox 2>/dev/null || cd "$(dirname "$0")/.." 2>/dev/null
if [ -f "lib/Pico-PIO-USB/CMakeLists.txt" ]; then
    echo "Submodules: OK"
else
    echo "Submodules: NOT INITIALIZED (need git submodule update --init --recursive)"
fi

echo ""
echo "Checking WSL Windows interop..."
if which cmd.exe >/dev/null 2>&1; then
    echo "Windows interop: available"
else
    echo "Windows interop: NOT available"
fi
