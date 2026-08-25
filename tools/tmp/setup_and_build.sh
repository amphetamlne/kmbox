#!/bin/bash
set -e

echo "========================================="
echo "  PIOKMbox 固件构建环境安装 & 构建"
echo "========================================="
echo ""

PROJECT_DIR="/mnt/d/Project/c++/kmbox"
PICO_SDK_DIR="$HOME/.pico-sdk/sdk/2.2.0-fresh"

# ---- Step 1: Install base build tools ----
echo "[1/5] 安装基础构建工具 (cmake, build-essential, git)..."
sudo apt-get update -qq
sudo apt-get install -y -qq cmake build-essential git pkg-config > /dev/null 2>&1
echo "  cmake: $(cmake --version | head -1)"
echo "  gcc: $(gcc --version | head -1)"
echo ""

# ---- Step 2: Install ARM toolchain ----
echo "[2/5] 安装 arm-none-eabi-gcc 工具链..."
# Try to install from apt first
if apt-cache show gcc-arm-none-eabi > /dev/null 2>&1; then
    sudo apt-get install -y -qq gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib > /dev/null 2>&1
    echo "  已安装: $(arm-none-eabi-gcc --version | head -1)"
else
    echo "  apt 中无 gcc-arm-none-eabi，尝试从 ARM 官网下载..."
    ARM_TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz"
    mkdir -p "$HOME/.local/arm-toolchain"
    cd "$HOME/.local/arm-toolchain"
    if [ ! -f "arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz" ]; then
        echo "  下载中 (约 800MB)..."
        wget -q --show-progress "$ARM_TOOLCHAIN_URL" -O arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz
    fi
    tar xf arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi.tar.xz
    TOOLCHAIN_BIN=$(ls -d "$HOME/.local/arm-toolchain"/arm-gnu-toolchain-*/bin | head -1)
    export PATH="$TOOLCHAIN_BIN:$PATH"
    # Add to .bashrc for persistence
    if ! grep -q "arm-gnu-toolchain" "$HOME/.bashrc" 2>/dev/null; then
        echo "export PATH=\"$TOOLCHAIN_BIN:\$PATH\"" >> "$HOME/.bashrc"
    fi
    echo "  已安装: $(arm-none-eabi-gcc --version | head -1)"
fi
echo ""

# ---- Step 3: Clone Pico SDK ----
echo "[3/5] 安装 Pico SDK 2.2.0..."
if [ -d "$PICO_SDK_DIR" ] && [ -f "$PICO_SDK_DIR/pico_sdk_init.cmake" ]; then
    echo "  Pico SDK 已存在于 $PICO_SDK_DIR，跳过"
else
    echo "  克隆 Pico SDK..."
    mkdir -p "$(dirname "$PICO_SDK_DIR")"
    if [ -d "$PICO_SDK_DIR" ]; then
        rm -rf "$PICO_SDK_DIR"
    fi
    git clone --branch 2.2.0 --depth 1 https://github.com/raspberrypi/pico-sdk.git "$PICO_SDK_DIR"
    cd "$PICO_SDK_DIR"
    git submodule update --init --recursive --depth 1
    echo "  Pico SDK 安装完成"
fi
export PICO_SDK_PATH="$PICO_SDK_DIR"
echo "  PICO_SDK_PATH=$PICO_SDK_PATH"
echo ""

# ---- Step 4: Init project submodules ----
echo "[4/5] 初始化项目 git submodules..."
cd "$PROJECT_DIR"
git submodule update --init --recursive
echo "  Submodules 初始化完成"
echo ""

# ---- Step 5: Build firmware ----
echo "[5/5] 构建固件 (metro target)..."
cd "$PROJECT_DIR"
export PICO_SDK_PATH="$PICO_SDK_DIR"
bash build.sh metro
echo ""

echo "========================================="
echo "  构建完成!"
echo "========================================="
if [ -f "$PROJECT_DIR/build-metro/PIOKMbox.uf2" ]; then
    SIZE=$(ls -lh "$PROJECT_DIR/build-metro/PIOKMbox.uf2" | awk '{print $5}')
    echo "  固件路径: build-metro/PIOKMbox.uf2 ($SIZE)"
else
    echo "  未找到输出固件，请检查上方构建日志"
fi
