# KMBox 固件构建指南（Windows 小白版）

> 本文档面向首次接触本项目的开发者，基于 Windows 11 + Git Bash 环境编写。

---

## 目录

1. [这个项目是做什么的](#1-这个项目是做什么的)
2. [你需要准备什么](#2-你需要准备什么)
3. [环境检查](#3-环境检查)
4. [构建固件](#4-构建固件)
5. [烧录固件到板子](#5-烧录固件到板子)
6. [常见问题排查](#6-常见问题排查)
7. [命令速查表](#7-命令速查表)

---

## 1. 这个项目是做什么的

KMBox 固件运行在 **RP2350** 微控制器板子上，核心功能是：

- 将鼠标/键盘通过 RP2350 做 USB 透传（电脑看到的是你的鼠标/键盘，不是板子）
- 同时接受串口命令来注入鼠标移动、点击、键盘输入
- 支持运动拟人化（防检测）

典型双板架构：

```
鼠标/键盘 ──► [板子1: KMBox主固件] ──► 电脑
                    ▲ UART串口（交叉连线）
                    ▼
               [板子2: Bridge固件] ──► ILI9341 显示屏
                    ▲ USB CDC
               [电脑/脚本]
```

---

## 2. 你需要准备什么

### 硬件

| 物品 | 说明 |
|:-----|:-----|
| **RP2350 板子** | 支持两种：Adafruit Metro RP2350 或 Waveshare RP2350-USB-A |
| **USB-C 数据线** | 连接板子和电脑（注意：不能用纯充电线） |
| **USB-A 设备** | 你要透传的鼠标或键盘 |
| （可选）第二块板子 | 如果需要 Bridge 功能（显示屏 + 自动瞄准） |

### 软件环境

以下工具**必须已安装**，如果缺失请参考 [第6节 常见问题](#6-常见问题排查)：

| 工具 | 怎么检查 | 安装方式 |
|:-----|:---------|:---------|
| **Git** | `git --version` | 官网下载安装 |
| **CMake** | `cmake --version` | 官网下载，勾选「加入 PATH」 |
| **Ninja** | `ninja --version` | `winget install Ninja-build.Ninja` |
| **Pico SDK 2.2.0** | 检查 `C:\Users\你的用户名\.pico-sdk\sdk\2.2.0-fresh` 是否存在 | 见下方说明 |
| **ARM 交叉编译器** | 检查 `C:\Users\你的用户名\.pico-sdk\toolchain\bin\arm-none-eabi-gcc.exe` | 见下方说明 |

### Pico SDK 和 ARM 编译器安装（如果还没有）

如果你之前用过 Raspberry Pi Pico 开发环境，大概率已经有了。检查方法：

```bash
# 在 Git Bash 中执行
ls ~/.pico-sdk/sdk/2.2.0-fresh/pico_sdk_init.cmake && echo "SDK 已安装"
ls ~/.pico-sdk/toolchain/bin/arm-none-eabi-gcc.exe && echo "编译器已安装"
```

如果缺失，最简单的方式是安装 **Raspberry Pi Pico VS Code 扩展**，它会自动帮你下载 SDK 和工具链。或者手动执行项目提供的安装脚本：

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/tmp/setup_win.ps1
```

> 这个脚本会自动下载 ARM 工具链（~900MB）和克隆 Pico SDK，需要耐心等待。

---

## 3. 环境检查

打开 **Git Bash**（不是 CMD，不是 PowerShell），依次执行：

```bash
# 检查 cmake
cmake --version
# 期望输出: cmake version 3.x.x 或更高

# 检查 ninja
ninja --version
# 期望输出: 1.x.x

# 检查 ARM 编译器
arm-none-eabi-gcc --version 2>/dev/null || ~/.pico-sdk/toolchain/bin/arm-none-eabi-gcc --version
# 期望输出: arm-none-eabi-gcc (GNU Toolchain ...) 14.2.x

# 检查 git
git --version
# 期望输出: git version 2.x.x
```

如果 `ninja` 找不到：

```bash
winget install --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements --silent
```

安装后**关闭并重新打开** Git Bash 再试。

---

## 4. 构建固件

### 4.1 进入项目目录

```bash
cd D:/Project/aimbot/kmbox
```

### 4.2 初始化子模块（首次或换分支后需要执行）

```bash
git submodule update --init --recursive
```

验证：

```bash
ls lib/Pico-PIO-USB/CMakeLists.txt
# 能看到文件路径就是成功
```

### 4.3 构建 KMBox 主固件

项目自带了一个 Windows 一键构建脚本，**直接用就行**：

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build_kmbox_windows.ps1
```

这个脚本默认构建 **Waveshare RP2350-USB-A** 板子的固件。

如果你用的是 **Adafruit Metro RP2350**，需要手动构建：

```bash
# 设置环境变量
export PICO_SDK_PATH="$HOME/.pico-sdk/sdk/2.2.0-fresh"
export PICO_TOOLCHAIN_PATH="$HOME/.pico-sdk/toolchain"
export HOME="$USERPROFILE"

# 配置 + 编译
cmake -S . -B build-metro -G Ninja \
  -DPICO_BOARD=adafruit_metro_rp2350 \
  -DPICO_PLATFORM=rp2350-arm-s \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build-metro -j $(nproc)
```

### 4.4 构建 Bridge 固件（可选，仅双板方案需要）

```bash
export PICO_SDK_PATH="$HOME/.pico-sdk/sdk/2.2.0-fresh"
export PICO_TOOLCHAIN_PATH="$HOME/.pico-sdk/toolchain"
export HOME="$USERPROFILE"

cmake -S bridge -B bridge/build-metro -G Ninja \
  -DPICO_BOARD=adafruit_metro_rp2350 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build bridge/build-metro -j $(nproc)
```

### 4.5 构建产物

| 固件 | 产出路径 | 大小约 |
|:-----|:---------|:-------|
| KMBox 主固件 (Waveshare) | `build-waveshare/PIOKMbox.uf2` | ~385 KB |
| KMBox 主固件 (Metro) | `build-metro/PIOKMbox.uf2` | ~385 KB |
| Bridge 固件 | `bridge/build-metro/kmbox_bridge.uf2` | ~200 KB |

> `.uf2` 就是最终要烧录到板子里的固件文件。

### 4.6 增量编译

修改代码后不需要重新走完整流程，直接执行构建命令即可：

```bash
# Waveshare 板子
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build_kmbox_windows.ps1

# 或手动 (Metro)
cmake --build build-metro -j $(nproc)
```

CMake 会自动检测哪些文件改了，只重新编译变化的部分，通常几秒到十几秒。

### 4.7 完全重新编译

如果遇到奇怪的编译错误，清掉构建目录重来：

```bash
# 清理 Waveshare 构建
rm -rf build-waveshare

# 清理 Metro 构建
rm -rf build-metro

# 清理 Bridge 构建
rm -rf bridge/build-metro
```

然后重新执行第 4.3 或 4.4 节的构建命令。

---

## 5. 烧录固件到板子

### 方法一：拖拽法（最简单，推荐新手）

1. **按住板子上的 BOOTSEL 按钮不松手**
2. 用 USB-C 线将板子连接到电脑
3. 松开 BOOTSEL 按钮
4. 电脑会识别出一个叫 `RPI-RP2` 的可移动磁盘
5. 把 `.uf2` 文件**复制粘贴**到这个磁盘里
6. 板子会自动重启，固件就烧好了

> 注意：如果板子已经在运行旧固件，需要先断电，然后按住 BOOTSEL 再上电。

### 方法二：picotool 命令行

```bash
# 烧录 KMBox 主固件
picotool load build-waveshare/PIOKMbox.uf2 -fx

# 烧录 Bridge 固件
picotool load bridge/build-metro/kmbox_bridge.uf2 -fx
```

> `-fx` 表示强制写入并执行。板子需要处于 BOOTSEL 模式或通过 picotool 进入。

### 双板烧录顺序

如果你有两块板子（KMBox + Bridge），需要分别烧录：

| 顺序 | 板子 | 固件文件 |
|:-----|:-----|:---------|
| 1 | KMBox 主板（接鼠标/键盘的那块） | `build-waveshare/PIOKMbox.uf2` 或 `build-metro/PIOKMbox.uf2` |
| 2 | Bridge 板（接显示屏的那块） | `bridge/build-metro/kmbox_bridge.uf2` |

### 双板接线

两块板子之间需要交叉连接 UART：

```
KMBox 板                    Bridge 板
GPIO0 (TX)  ──────────────►  GPIO1 (RX)
GPIO1 (RX)  ◄──────────────  GPIO0 (TX)
GND         ───────────────  GND
```

> 两块板子上的 TX/RX 拨码开关都要拨到：TX=GPIO0，RX=GPIO1。

---

## 6. 常见问题排查

### Q: CMake 报错说 CMakeCache.txt 目录不匹配

```
CMake Error: The current CMakeCache.txt directory ... is different than ...
```

**原因**：项目路径变了（比如从 `D:/Project/c++/kmbox` 移到了 `D:/Project/aimbot/kmbox`），旧的缓存文件还记着老路径。

**解决**：删掉构建目录重新来：

```bash
rm -rf build-waveshare build-metro bridge/build-metro
```

### Q: 找不到 ninja

```
cmake: error: could not find ninja
```

**解决**：

```bash
winget install --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements --silent
```

安装后**重启 Git Bash**。

### Q: 找不到 arm-none-eabi-gcc

**原因**：ARM 交叉编译器没装或不在 PATH 里。

**解决**：检查是否已安装：

```bash
ls ~/.pico-sdk/toolchain/bin/arm-none-eabi-gcc.exe
```

如果存在，构建时会自动使用。如果不存在，运行安装脚本：

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/tmp/setup_win.ps1
```

### Q: 找不到 Pico SDK

```
CMake Error: Could not find PICO_SDK_PATH
```

**解决**：在构建前设置环境变量：

```bash
export PICO_SDK_PATH="$HOME/.pico-sdk/sdk/2.2.0-fresh"
export PICO_TOOLCHAIN_PATH="$HOME/.pico-sdk/toolchain"
```

### Q: 编译过程中出现大量 warning

**结论**：**不用管，正常现象。** 编译器输出的 warning（警告）不影响最终固件。只要最后看到类似以下输出就是成功：

```
>>> 编译成功: D:\Project\aimbot\kmbox\build-waveshare\PIOKMbox.uf2 (394752 bytes)
```

### Q: 编译报错 `undefined reference` 或链接失败

**原因**：子模块没初始化完整。

**解决**：

```bash
git submodule update --init --recursive
rm -rf build-waveshare   # 清掉旧的构建目录
# 然后重新构建
```

### Q: 板子插上电脑没反应 / 不出现 RPI-RP2 磁盘

- 换一根数据线（有些线只能充电不能传数据）
- 换一个 USB 口
- 确认你按住 BOOTSEL 的时间够长（板子断电状态下按住，然后通电，等 2 秒再松）

### Q: 拖拽 uf2 后板子没重启

- 检查文件是否真的复制成功了（文件大小应该和构建产物一致）
- 尝试用 picotool 烧录
- 检查 USB 供电是否稳定（不要用 USB Hub）

---

## 7. 命令速查表

### 完整构建流程（复制粘贴即可）

```bash
# ===== 进入项目目录 =====
cd D:/Project/aimbot/kmbox

# ===== 首次需要：初始化子模块 =====
git submodule update --init --recursive

# ===== 构建 KMBox 主固件 (Waveshare 板子) =====
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build_kmbox_windows.ps1

# ===== 构建 KMBox 主固件 (Metro 板子，二选一) =====
export PICO_SDK_PATH="$HOME/.pico-sdk/sdk/2.2.0-fresh"
export PICO_TOOLCHAIN_PATH="$HOME/.pico-sdk/toolchain"
export HOME="$USERPROFILE"
cmake -S . -B build-metro -G Ninja -DPICO_BOARD=adafruit_metro_rp2350 -DPICO_PLATFORM=rp2350-arm-s -DCMAKE_BUILD_TYPE=Release
cmake --build build-metro -j $(nproc)

# ===== 构建 Bridge 固件（可选） =====
cmake -S bridge -B bridge/build-metro -G Ninja -DPICO_BOARD=adafruit_metro_rp2350 -DCMAKE_BUILD_TYPE=Release
cmake --build bridge/build-metro -j $(nproc)

# ===== 烧录（拖拽法不需要命令行） =====
picotool load build-waveshare/PIOKMbox.uf2 -fx
```

### 清理 + 重建

```bash
rm -rf build-waveshare build-metro bridge/build-metro
# 然后重新执行上面的构建命令
```

### 板子选择对照表

| 你的板子 | CMake 参数 | 构建脚本 |
|:---------|:-----------|:---------|
| Waveshare RP2350-USB-A | `-DPICO_BOARD=waveshare_rp2350_usb_a` | `tools/build_kmbox_windows.ps1` |
| Adafruit Metro RP2350 | `-DPICO_BOARD=adafruit_metro_rp2350` | 手动 cmake 命令 |
| Raspberry Pi Pico 2 | `-DPICO_BOARD=pico2` | `./build.sh pico2` |

---

## 附录：目录结构速览

```
kmbox/
├── PIOKMbox.c                 # 主固件入口
├── CMakeLists.txt             # 主固件构建配置
├── build.sh                   # Linux/Mac 构建脚本
├── boards/                    # 板子引脚定义
├── lib/                       # 依赖库（git 子模块）
│   ├── Pico-PIO-USB/          #   PIO USB 库
│   ├── kmbox-commands/        #   KMBox 命令解析
│   ├── hid-defs/              #   HID 定义
│   ├── fast-protocol/         #   快速二进制协议
│   ├── wire-protocol/         #   线路格式工具
│   ├── dma-uart/              #   DMA 串口
│   ├── peri-clock/            #   外设时钟
│   └── led-utils/             #   LED 控制
├── bridge/                    # Bridge 固件（第二块板子）
│   ├── CMakeLists.txt
│   ├── main.c
│   └── ...
├── tools/                     # 辅助工具
│   ├── build_kmbox_windows.ps1  # Windows 一键构建脚本
│   └── ...
├── build-waveshare/           # Waveshare 构建产物（构建后生成）
│   └── PIOKMbox.uf2           # ← 这就是你要烧录的文件
└── build-metro/               # Metro 构建产物（构建后生成）
    └── PIOKMbox.uf2           # ← 这就是你要烧录的文件
```
