#!/bin/bash
# 环境检查脚本
echo "PICO_SDK_PATH=${PICO_SDK_PATH:-<unset>}"
for cmd in cmake make arm-none-eabi-gcc picotool ninja git; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "[OK]   $cmd -> $(command -v "$cmd")"
    else
        echo "[MISS] $cmd"
    fi
done
echo "--- ~/.pico-sdk 内容 ---"
ls "$USERPROFILE/.pico-sdk" 2>/dev/null || echo "(不存在)"
echo "--- SDK 版本 ---"
ls "$USERPROFILE/.pico-sdk/sdk" 2>/dev/null
cmake --version 2>/dev/null | head -1
arm-none-eabi-gcc --version 2>/dev/null | head -1
